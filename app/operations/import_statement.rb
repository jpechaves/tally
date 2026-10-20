# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

module Tally
  module Operations
    # Imports one statement file (docs/statement-import.md, section 4):
    #
    # 1. The same bytes already in effect (the latest applied version of that statement):
    #    logged as duplicate_file, nothing else. Bytes applied before but since replaced by
    #    an edited copy are applied again.
    # 2. Parse and check. A file that fails is logged as rejected, and nothing else is
    #    written.
    # 3. In one DB transaction: upsert each row by (account, external_id), flag rows the
    #    file no longer has, link card merchants to the same company paid with a CNPJ,
    #    pair transfers, categorize, and log the import with its counts.
    # 4. Keep the original file under the import storage folder, named by its SHA-256.
    #
    # Every outcome is an `imports` row: Success(import) when applied or a duplicate,
    # Failure(import) when rejected.
    class ImportStatement < Tally::Operation
      include Deps[
        "settings",
        "repos.account_repo",
        "repos.counterparty_repo",
        "repos.import_repo",
        "repos.transaction_repo",
        "operations.pair_transfers",
        "operations.categorize"
      ]

      # Fields that come from the bank and are updated on re-import. Everything else
      # (memo, the category) belongs to you or to the categorizer, and is never touched.
      BANK_FIELDS = %i[
        occurred_on purchased_on amount_cents kind description raw_description bank_category
        location installment_number installment_total purchase_key counterparty_id
        counter_account_id card_statement_id exchange_currency exchange_amount_cents exchange_rate
        fee_cents raw_json
      ].freeze

      EXTENSIONS = {"itau_card_pdf" => "pdf"}.freeze

      # @param person_id [Integer, nil] whose statement it is (issue #21); nil for yours
      def call(file_name:, content:, person_id: nil)
        content = content.b
        file = {file_name: File.basename(file_name.to_s), file_sha256: Digest::SHA256.hexdigest(content),
                file_size: content.bytesize}

        previous = import_repo.applied_with_sha(file[:file_sha256])
        if previous && import_repo.in_effect?(previous)
          return import_repo.create(**file, status: "duplicate_file", source: previous.source,
            account_id: previous.account_id, period_start: previous.period_start, period_end: previous.period_end)
        end

        statement = begin
          Importers.parse(file[:file_name], content).tap { same_currency!(_1) }
        rescue Importers::Error => e
          step Failure(import_repo.create(**file, status: "rejected", source: source_of(content), error: e.notice))
        end

        import = transaction { apply(statement, file, person_id) }
        store(content, file[:file_sha256], statement.source)
        import
      end

      private

      def apply(statement, file, person_id)
        account = account_repo.ensure(statement.account_name, person_id:)
        import = import_repo.create(**file, status: "applied", source: statement.source, account_id: account.id,
          period_start: statement.period_start.iso8601, period_end: statement.period_end.iso8601,
          warnings: statement.warnings)

        card_statement_id = if statement.card_statement
          transaction_repo.upsert_card_statement(account_id: account.id, import_id: import.id,
            figures: statement.card_statement)
        end

        counts = Hash.new(0)
        known = transaction_repo.by_external_ids(account.id, statement.rows.map(&:external_id))
        # The same person's other accounts (the card a bill payment paid), and the accounts
        # of the household a Pix went to, each looked up once.
        account_ids = Hash.new { |ids, name| ids[name] = account_repo.ensure(name, person_id: account.person_id).id }
        counter_ids = Hash.new do |ids, (template, person)|
          ids[[template, person]] = account_repo.counter_account_id(template, person, from: account.id)
        end
        ids = statement.rows.map do |row|
          attributes = attributes(row, card_statement_id, account_ids, counter_ids)
          existing = known[row.external_id]

          if existing.nil?
            counts[:inserted] += 1
            transaction_repo.insert(**attributes, account_id: account.id, external_id: row.external_id,
              first_import_id: import.id, last_import_id: import.id)
          else
            changes = attributes.slice(*BANK_FIELDS).reject { |field, value| existing[field] == value }
            counts[changes.empty? ? :unchanged : :updated] += 1
            transaction_repo.update(existing[:id], **changes, last_import_id: import.id, missing_since_import_id: nil)
            existing[:id]
          end
        end

        missing = transaction_repo.flag_missing(
          account_id: account.id, import_id: import.id, keep_ids: ids,
          **(card_statement_id ? {card_statement_id:} : {period: statement.period_start..statement.period_end})
        )
        linked = counterparty_repo.link_merchants
        pair_transfers.call(touched_ids: ids)
        categorize.call(ids: ids | linked)

        import_repo.update(import.id, rows_inserted: counts[:inserted], rows_updated: counts[:updated],
          rows_unchanged: counts[:unchanged], rows_missing: missing)
      end

      # Amounts are stored in their account's currency, so a parser that read another one
      # would mix currencies in one balance.
      def same_currency!(statement)
        currency = Importers::ACCOUNTS.fetch(statement.account_name).fetch(:currency, Money::DEFAULT_CURRENCY)
        wrong = statement.rows.find { _1.amount.currency != currency }
        if wrong
          raise Importers::Error.new(:wrong_currency, text: wrong.raw_description, found: wrong.amount.currency,
            account: statement.account_name, currency:)
        end
      end

      # @param account_ids [Hash] account name => id, the account created the first time
      # @param counter_ids [Hash] [account kind, person id] => the account a Pix to them went to
      def attributes(row, card_statement_id, account_ids, counter_ids)
        counterparty = row.counterparty && counterparty_repo.upsert(**row.counterparty)
        kind = row.kind
        counter_account_id = row.counter_account && account_ids[row.counter_account]

        # A Pix between people of the household (you and yourself at another bank, or you
        # and your partner) is a transfer, not spending.
        if counterparty&.is_self == 1 && %w[purchase income].include?(kind)
          kind = "transfer"
          counter_account_id = counter_ids[[Importers.account_at(row.raw_description), counterparty.person_id]]
        end

        {
          occurred_on: row.occurred_on.iso8601,
          purchased_on: row.purchased_on&.iso8601,
          amount_cents: row.amount.cents,
          kind:,
          description: row.description,
          raw_description: row.raw_description,
          bank_category: row.bank_category,
          location: row.location,
          installment_number: row.installment_number,
          installment_total: row.installment_total,
          purchase_key: row.purchase_key,
          counterparty_id: counterparty&.id,
          counter_account_id:,
          card_statement_id:,
          exchange_currency: row.exchange_currency,
          exchange_amount_cents: row.exchange_amount&.cents,
          exchange_rate: row.exchange_rate,
          fee_cents: row.fee&.cents,
          raw_json: JSON.generate(row.raw)
        }
      end

      def store(content, sha, source)
        dir = File.expand_path(settings.import_storage_dir, Hanami.app.root)
        path = File.join(dir, "#{sha}.#{EXTENSIONS.fetch(source, "csv")}")
        return if File.exist?(path)

        FileUtils.mkdir_p(dir)
        File.binwrite(path, content)
      end

      def source_of(content)
        Importers.for(content).class::SOURCE
      rescue Importers::Error
        "unknown"
      end
    end
  end
end
