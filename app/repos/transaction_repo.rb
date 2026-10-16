# frozen_string_literal: true

module Tally
  module Repos
    # Transactions, plus the rows that hang off them on import: card statements and
    # transfers. Works on plain hashes from the Sequel datasets, because the import
    # compares and updates column by column.
    class TransactionRepo < Tally::DB::Repo
      MIRROR_PREFIX = "mirror:"

      # The kinds behind each Tally::TransactionFilter kind; the counted ones match the report.
      KIND_FILTERS = {
        "spending" => Tally::Insights::SPENDING_KINDS, "income" => Tally::Insights::INCOME_KINDS, "transfer" => %w[transfer]
      }.freeze
      COUNTED = %w[spending income].freeze

      # --- Reading --------------------------------------------------------------------

      def by_external_id(account_id, external_id)
        transactions.dataset.where(account_id:, external_id:).first
      end

      def row(id) = transactions.dataset.where(id:).first

      def rows(ids) = transactions.dataset.where(id: ids).order(:id).all

      # A page of transactions, newest first, with account and counterparty names.
      # @param filter [Tally::TransactionFilter]
      def list(filter = Tally::TransactionFilter.new, import_id: nil, missing: false, id: nil, limit: 500, offset: 0)
        scope = transactions.dataset
          .join(:accounts, id: :account_id)
          .left_join(:counterparties, id: Sequel[:transactions][:counterparty_id])
          .left_join(Sequel[:accounts].as(:counter_accounts), id: Sequel[:transactions][:counter_account_id])
          .left_join(:categories, id: Sequel[:transactions][:category_id])
          .select_all(:transactions)
          .select_append(
            Sequel[:accounts][:name].as(:account_name),
            Sequel[:counterparties][:name].as(:counterparty_name),
            Sequel[:counterparties][:document].as(:counterparty_document),
            Sequel[:counter_accounts][:name].as(:counter_account_name),
            Sequel[:categories][:name].as(:category_name)
          )
        scope = scope.where(Sequel[:transactions][:id] => id) if id
        scope = filtered(scope, filter)
        scope = scope.where(Sequel[:transactions][:missing_since_import_id] => import_id) if missing && import_id
        scope = scope.where(Sequel[:transactions][:last_import_id] => import_id) if import_id && !missing
        scope.order(Sequel.desc(Sequel[:transactions][:occurred_on]), Sequel.desc(Sequel[:transactions][:id]))
          .limit(limit, offset).all
      end

      # How many rows match the filter, and their net, across all pages.
      def totals(filter = Tally::TransactionFilter.new)
        scope = filtered(transactions.dataset.unordered, filter)
        {rows: scope.count, total_cents: scope.sum(Sequel[:transactions][:amount_cents]) || 0}
      end

      # Months that have rows, newest first ("2026-09", ...).
      def months
        transactions.dataset.unordered
          .select(Sequel.function(:substr, :occurred_on, 1, 7).as(:month)).distinct
          .order(Sequel.desc(:month)).map(:month)
      end

      def ids_for_counterparty(counterparty_id)
        transactions.dataset.where(counterparty_id:).select_map(:id)
      end

      # --- Categories -----------------------------------------------------------------

      CATEGORIZER_COLUMNS = %i[
        id kind amount_cents description raw_description bank_category category_id category_source category_rule_id
      ].freeze

      # Rows the categorizer may change (every one but manual), with what it looks at.
      # @param ids [Array<Integer>, nil] nil for every row
      def for_categorizing(ids: nil)
        scope = transactions.dataset.exclude(Sequel[:transactions][:category_source] => "manual")
          .left_join(:counterparties, id: :counterparty_id)
          .select(*CATEGORIZER_COLUMNS.map { Sequel[:transactions][_1] })
          .select_append(
            Sequel[:counterparties][:name].as(:counterparty_name),
            Sequel[:counterparties][:document].as(:counterparty_document),
            Sequel[:counterparties][:default_category_id]
          )
        scope = scope.where(Sequel[:transactions][:id] => ids) if ids
        scope.order(Sequel[:transactions][:id]).all
      end

      def set_category(ids, category_id:, category_source:, category_rule_id: nil)
        transactions.dataset.where(id: ids)
          .update(category_id:, category_source:, category_rule_id:, updated_at: Repos.now)
      end

      # What the review list shows: rows that count as spending or income and have no
      # category yet, or only the bank's suggestion. Rows a re-import flagged as missing
      # are left out.
      def to_review
        transactions.dataset
          .exclude(Sequel[:transactions][:kind] => "transfer")
          .where(Sequel[:transactions][:category_source] => %w[none bank], missing_since_import_id: nil)
          .join(:accounts, id: :account_id)
          .left_join(:counterparties, id: Sequel[:transactions][:counterparty_id])
          .left_join(:categories, id: Sequel[:transactions][:category_id])
          .select_all(:transactions)
          .select_append(
            Sequel[:accounts][:name].as(:account_name),
            Sequel[:counterparties][:name].as(:counterparty_name),
            Sequel[:counterparties][:document].as(:counterparty_document),
            Sequel[:categories][:name].as(:category_name)
          )
          .order(Sequel.desc(Sequel[:transactions][:occurred_on]), Sequel.desc(Sequel[:transactions][:id]))
          .all
      end

      # --- Writing --------------------------------------------------------------------

      def insert(attributes) = transactions.dataset.insert(attributes)

      def update(id, attributes)
        transactions.dataset.where(id:).update(**attributes, updated_at: Repos.now)
      end

      # Flags rows of this account that the new file no longer has (statement-import.md,
      # section 4, step 5). They are kept, never deleted.
      #
      # @param scope [Hash] {card_statement_id:} for a card bill, or {period: Range} for an
      #   account statement
      # @return [Integer] how many rows are now flagged
      def flag_missing(account_id:, import_id:, keep_ids:, card_statement_id: nil, period: nil)
        scope = transactions.dataset.where(account_id:, missing_since_import_id: nil)
          .exclude(id: keep_ids)
          .exclude(Sequel.like(:external_id, "#{MIRROR_PREFIX}%"))
        scope = if card_statement_id
          scope.where(card_statement_id:)
        else
          scope.where(card_statement_id: nil, occurred_on: period.begin.iso8601..period.end.iso8601)
        end

        scope.update(missing_since_import_id: import_id, updated_at: Repos.now)
      end

      # @return [Integer] the card statement's id
      def upsert_card_statement(account_id:, import_id:, figures:)
        attributes = figures.transform_values { _1.is_a?(Date) ? _1.iso8601 : _1 }.merge(import_id:)
        statements = card_statements.dataset
        existing = statements.where(account_id:, due_on: attributes[:due_on]).first

        if existing
          statements.where(id: existing[:id]).update(**attributes, updated_at: Repos.now)
          existing[:id]
        else
          statements.insert(account_id:, **attributes)
        end
      end

      def card_statements_for(account_id) = card_statements.dataset.where(account_id:).order(:due_on).all

      def card_statement(id) = card_statements.dataset.where(id:).first

      # Each card's latest bill, with what the bank says is already committed to the next
      # ones (Itaú prints it; Nubank's CSV doesn't).
      def card_statements_with_account
        latest = card_statements.dataset.unordered.group(:account_id).select { max(:due_on).as(:due_on) }.select_append(:account_id)
        card_statements.dataset
          .join(latest.as(:latest), account_id: :account_id, due_on: :due_on)
          .join(:accounts, id: Sequel[:card_statements][:account_id])
          .select_all(:card_statements).select_append(Sequel[:accounts][:name].as(:account_name))
          .order(Sequel[:accounts][:name]).all
      end

      # --- Transfers ------------------------------------------------------------------

      def unpaired_transfers
        transactions.dataset.where(kind: "transfer", transfer_id: nil).exclude(counter_account_id: nil)
          .order(:occurred_on, :id).all
      end

      def transfer_legs(transfer_id) = transactions.dataset.where(transfer_id:).order(:id).all

      # The other leg of a transfer between two imported accounts: same amount with the
      # opposite sign, pointing back at this account, within a few days.
      def find_partner(row, days: 5)
        date = Date.iso8601(row[:occurred_on])
        transactions.dataset
          .where(account_id: row[:counter_account_id], counter_account_id: row[:account_id],
            kind: "transfer", transfer_id: nil, amount_cents: -row[:amount_cents])
          .where(occurred_on: (date - days).iso8601..(date + days).iso8601)
          .exclude(id: row[:id])
          .order(Sequel.function(:abs, Sequel.function(:julianday, :occurred_on) - Sequel.function(:julianday, row[:occurred_on])), :id)
          .first
      end

      def create_transfer(occurred_on:, leg_ids:)
        id = transfers.dataset.insert(occurred_on:)
        transactions.dataset.where(id: leg_ids).update(transfer_id: id, updated_at: Repos.now)
        id
      end

      def delete_transfer(transfer_id)
        transactions.dataset.where(transfer_id:).update(transfer_id: nil, updated_at: Repos.now)
        transfers.dataset.where(id: transfer_id).delete
      end

      def delete_mirror(id)
        transactions.dataset.where(id:).where(Sequel.like(:external_id, "#{MIRROR_PREFIX}%")).delete
      end

      def mirror?(row) = row[:external_id].start_with?(MIRROR_PREFIX)

      def mirror_external_id(source_id) = "#{MIRROR_PREFIX}#{source_id}"

      private

      # Narrows a transactions dataset to a Tally::TransactionFilter.
      def filtered(scope, filter)
        column = ->(name) { Sequel[:transactions][name] }
        scope = scope.where(column.(:account_id) => filter.account) if filter.account
        scope = scope.where(Sequel.function(:substr, column.(:occurred_on), 1, 7) => filter.month) if filter.month
        scope = scope.where(column.(:category_id) => category_ids(filter.category)) if filter.category
        scope = scope.where(column.(:kind) => KIND_FILTERS.fetch(filter.kind)) if filter.kind
        # Spending and income as the report counts them, which leaves out rows a
        # re-import flagged as missing (InsightRepo).
        scope = scope.where(column.(:missing_since_import_id) => nil) if COUNTED.include?(filter.kind)
        scope
      end

      # A category and, for a parent, its children; nil (no category) for NONE.
      def category_ids(category)
        return nil if category == Tally::TransactionFilter::NONE

        categories.dataset.unordered.where(Sequel.|({id: category}, {parent_id: category})).select(:id)
      end
    end
  end
end
