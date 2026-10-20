# frozen_string_literal: true

module Tally
  module Repos
    # Transactions, plus the rows that hang off them on import: card statements
    # (Writing) and transfers (Transfers). Works on plain hashes from the Sequel datasets,
    # because the import compares and updates column by column.
    class TransactionRepo < Tally::DB::Repo
      include Deps["repos.trip_repo"]
      include Writing
      include Transfers

      MIRROR_PREFIX = "mirror:"

      # The kinds behind each Tally::TransactionFilter kind; the counted ones match the report.
      KIND_FILTERS = {
        "spending" => Tally::Insights::SPENDING_KINDS, "income" => Tally::Insights::INCOME_KINDS, "transfer" => %w[transfer]
      }.freeze
      COUNTED = %w[spending income].freeze

      TRANSACTIONS = Sequel[:transactions]
      ACCOUNTS = Sequel[:accounts]
      COUNTERPARTIES = Sequel[:counterparties]
      NEWEST_FIRST = [Sequel.desc(TRANSACTIONS[:occurred_on]), Sequel.desc(TRANSACTIONS[:id])].freeze

      # --- Reading --------------------------------------------------------------------

      def by_external_id(account_id, external_id)
        transactions.dataset.where(account_id:, external_id:).first
      end

      # external_id => row, for the rows of the account already there with these ids.
      def by_external_ids(account_id, external_ids)
        transactions.dataset.where(account_id:, external_id: external_ids).to_hash(:external_id)
      end

      def row(id) = transactions.dataset.where(id:).first

      def rows(ids) = transactions.dataset.where(id: ids).order(:id).all

      # A page of transactions, newest first, with account and counterparty names, and what
      # each counts as after your adjustment (Tally::Adjustments.columns).
      # @param filter [Tally::TransactionFilter]
      def list(filter = Tally::TransactionFilter.new, import_id: nil, missing: false, id: nil, limit: 500, offset: 0)
        scope = named(transactions.dataset)
          .left_join(ACCOUNTS.as(:counter_accounts), id: TRANSACTIONS[:counter_account_id])
          .then { Tally::Adjustments.join(_1) }
          .select_append(Sequel[:counter_accounts][:name].as(:counter_account_name), *Tally::Adjustments.columns)
        scope = scope.where(TRANSACTIONS[:id] => id) if id
        scope = filtered(scope, filter)
        scope = scope.where(TRANSACTIONS[missing ? :missing_since_import_id : :last_import_id] => import_id) if import_id
        scope.order(*NEWEST_FIRST).limit(limit, offset).all
      end

      # How many rows match the filter, and their net in each currency, across all pages, as
      # the rows count after your adjustments.
      # @return [Hash] rows:, net: {"BRL" => cents, "USD" => cents}, reais first
      def totals(filter = Tally::TransactionFilter.new)
        scope = filtered(transactions.dataset.unordered, filter)
        net = Tally::Adjustments.join(scope.join(:accounts, id: TRANSACTIONS[:account_id]))
          .group(ACCOUNTS[:currency])
          .select(ACCOUNTS[:currency], Sequel.function(:sum, Tally::Adjustments.counted_amount).as(:cents))
          .to_h { [_1[:currency], _1[:cents]] }
        {rows: scope.count, net: net.sort_by { |currency, _| (currency == Tally::Money::DEFAULT_CURRENCY) ? "" : currency }.to_h}
      end

      # Months that have rows, newest first ("2026-09", ...), in one account if given.
      def months(account_id: nil)
        scope = account_id ? transactions.dataset.where(account_id:) : transactions.dataset
        scope.unordered
          .select(Sequel.function(:substr, :occurred_on, 1, 7).as(:month)).distinct
          .order(Sequel.desc(:month)).map(:month)
      end

      # The installments of the card purchase that the row with this id is part of, in bill
      # order (Tally::InstallmentCalendar.series), with what InstallmentCalendar::Purchase
      # needs. Empty when the row isn't an installment.
      def installment_series(id)
        row = transactions.dataset.where(id:).exclude(installment_total: nil).first
        return [] unless row

        rows = transactions.dataset
          .where(TRANSACTIONS[:account_id] => row[:account_id], TRANSACTIONS[:installment_total] => row[:installment_total],
            TRANSACTIONS[:missing_since_import_id] => nil)
          .exclude(TRANSACTIONS[:kind] => "transfer")
          .join(:accounts, id: TRANSACTIONS[:account_id])
          .left_join(:card_statements, id: TRANSACTIONS[:card_statement_id])
          .select_all(:transactions)
          .select_append(ACCOUNTS[:name].as(:account_name), Sequel[:card_statements][:due_on].as(:bill_due_on))
          .all
        Tally::InstallmentCalendar.series_of(rows, id)
      end

      # The ids and kinds of every row the filter matches, on every page.
      def matching(filter)
        filtered(transactions.dataset.unordered, filter).select(TRANSACTIONS[:id], TRANSACTIONS[:kind]).all
      end

      def ids_for_counterparty(counterparty_id)
        transactions.dataset.where(counterparty_id:).select_map(:id)
      end

      # --- Categories -----------------------------------------------------------------

      CATEGORIZER_COLUMNS = %i[
        id kind amount_cents description raw_description bank_category category_id category_source category_rule_id
      ].freeze

      # Rows the categorizer may change (every one but manual), with what it looks at. Rules
      # match the counterparty's name as the bank wrote it, never your display name.
      # @param ids [Array<Integer>, nil] nil for every row
      def for_categorizing(ids: nil)
        scope = transactions.dataset.exclude(TRANSACTIONS[:category_source] => "manual")
          .left_join(:counterparties, id: :counterparty_id)
          .select(*CATEGORIZER_COLUMNS.map { TRANSACTIONS[_1] })
          .select_append(
            COUNTERPARTIES[:name].as(:counterparty_name),
            COUNTERPARTIES[:document].as(:counterparty_document),
            COUNTERPARTIES[:default_category_id]
          )
        scope = scope.where(TRANSACTIONS[:id] => ids) if ids
        scope.order(TRANSACTIONS[:id]).all
      end

      def set_category(ids, category_id:, category_source:, category_rule_id: nil)
        transactions.dataset.where(id: ids)
          .update(category_id:, category_source:, category_rule_id:, updated_at: Repos.now)
      end

      # What the review list shows: rows that count as spending or income and have no
      # category yet, or only the bank's suggestion. Rows a re-import flagged as missing
      # are left out, and so are rows your adjustment says count as nothing.
      def to_review
        scope = transactions.dataset
          .exclude(TRANSACTIONS[:kind] => "transfer")
          .exclude(TRANSACTIONS[:id] => Tally::Adjustments.uncounted_ids(transactions.dataset))
          .where(TRANSACTIONS[:category_source] => %w[none bank], :missing_since_import_id => nil)
        named(scope).order(*NEWEST_FIRST).all
      end

      # --- Adjustments (Tally::Adjustments) --------------------------------------------

      def adjustment(transaction_id) = transaction_adjustments.dataset.where(transaction_id:).first

      # The adjustment whose reimbursement this row paid, if any.
      def refund_link(refund_transaction_id) = transaction_adjustments.dataset.where(refund_transaction_id:).first

      # One adjustment per row: a new one replaces the old.
      def save_adjustment(transaction_id, kind:, amount_cents: nil, refund_transaction_id: nil, note: nil)
        attributes = {kind:, amount_cents:, refund_transaction_id:, note:}
        transaction_adjustments.dataset.insert_conflict(
          target: :transaction_id, update: attributes.to_h { [_1, Sequel[:excluded][_1]] }.merge(updated_at: Repos.now)
        ).insert(transaction_id:, **attributes)
      end

      def remove_adjustment(transaction_id) = transaction_adjustments.dataset.where(transaction_id:).delete

      # Rows that could have paid a purchase back: money coming in that is spending or
      # income (not a transfer), up to the purchase's amount, near its date, not already
      # counted inside another purchase nor adjusted itself, in the same currency. Closest
      # date first.
      # @param row [Hash] a row from #list
      def refund_candidates(row, limit: 20)
        adjustments = transaction_adjustments.dataset
        linked = adjustments.exclude(refund_transaction_id: nil).exclude(transaction_id: row[:id]).select(:refund_transaction_id)
        amount = TRANSACTIONS[:amount_cents]
        transactions.dataset
          .join(:accounts, id: :account_id)
          .where(ACCOUNTS[:currency] => row[:currency], TRANSACTIONS[:missing_since_import_id] => nil,
            TRANSACTIONS[:kind] => Tally::Insights::SPENDING_KINDS + Tally::Insights::INCOME_KINDS,
            TRANSACTIONS[:occurred_on] => around(row, Tally::Adjustments::REFUND_WINDOW))
          .where((amount > 0) & (amount <= row[:amount_cents].abs))
          .exclude(TRANSACTIONS[:id] => linked)
          .exclude(TRANSACTIONS[:id] => adjustments.select(:transaction_id))
          .select_all(:transactions).select_append(ACCOUNTS[:name].as(:account_name))
          .order(closest_to(row, TRANSACTIONS[:occurred_on]), TRANSACTIONS[:id])
          .limit(limit)
          .all
      end

      private

      # Rows with their account's name and currency, their counterparty's names and their
      # category's name.
      def named(scope)
        scope
          .join(:accounts, id: TRANSACTIONS[:account_id])
          .left_join(:counterparties, id: TRANSACTIONS[:counterparty_id])
          .left_join(:categories, id: TRANSACTIONS[:category_id])
          .select_all(:transactions)
          .select_append(
            ACCOUNTS[:name].as(:account_name),
            ACCOUNTS[:currency],
            *Tally::DB::Repo.counterparty_columns,
            COUNTERPARTIES[:document].as(:counterparty_document),
            Sequel[:categories][:name].as(:category_name)
          )
      end

      # The dates (as stored, "YYYY-MM-DD") this many days around the row's.
      # @param days [Range<Integer>]
      def around(row, days)
        date = Date.iso8601(row[:occurred_on])
        (date + days.begin).iso8601..(date + days.end).iso8601
      end

      # Days between the column's date and the row's, for ordering by the closest.
      def closest_to(row, column = :occurred_on)
        Sequel.function(:abs, Sequel.function(:julianday, column) - Sequel.function(:julianday, row[:occurred_on]))
      end

      # Narrows a transactions dataset to a Tally::TransactionFilter.
      def filtered(scope, filter)
        scope = scope.where(TRANSACTIONS[:account_id] => filter.account) if filter.account
        scope = scope.where(Sequel.function(:substr, TRANSACTIONS[:occurred_on], 1, 7) => filter.month) if filter.month
        scope = scope.where(TRANSACTIONS[:category_id] => category_ids(filter.category)) if filter.category
        scope = scope.where(TRANSACTIONS[:kind] => KIND_FILTERS.fetch(filter.kind)) if filter.kind
        scope = scope.where(nature_condition(filter.nature)) if filter.nature
        scope = scope.where(payee_key => filter.payee) if filter.payee
        scope = scope.where(TRANSACTIONS[:id] => installment_series(filter.purchase).map { _1[:id] }) if filter.purchase
        scope = scope.where(TRANSACTIONS[:id] => trip_ids(filter.trip)) if filter.trip
        scope = scope.where(Tally::TransactionSearch.condition(filter.q, transactions.dataset)) if filter.q
        COUNTED.include?(filter.kind) ? counted(scope) : scope
      end

      # Spending and income as the report counts them, which leaves out rows a re-import
      # flagged as missing, rows dated after today and rows your adjustment says count as
      # nothing (InsightRepo).
      def counted(scope)
        scope.where(TRANSACTIONS[:missing_since_import_id] => nil)
          .where(TRANSACTIONS[:occurred_on] <= Date.today.iso8601)
          .exclude(TRANSACTIONS[:id] => Tally::Adjustments.uncounted_ids(transactions.dataset))
      end

      def trip_ids(id)
        trip = trip_repo.find(id)
        trip ? trip_repo.build(trip).ids : []
      end

      # A category and, for a parent, its children; nil (no category) for NONE.
      def category_ids(category)
        return nil if category == Tally::TransactionFilter::NONE

        categories.dataset.unordered.where(Sequel.|({id: category}, {parent_id: category})).select(:id)
      end

      # Who a row paid, grouped like the review list and the report (Tally::Review.key).
      def payee_key
        Sequel.function(Tally::Review::KEY_FUNCTION, TRANSACTIONS[:counterparty_id], TRANSACTIONS[:description])
      end

      # Rows whose own category has this nature. UNSET is rows whose category has none and
      # rows with no category, as the report groups them.
      def nature_condition(nature)
        category_id = TRANSACTIONS[:category_id]
        return {category_id => categories.dataset.unordered.where(nature:).select(:id)} unless nature == Tally::TransactionFilter::UNSET

        Sequel.|({category_id => nil}, {category_id => categories.dataset.unordered.where(nature: nil).select(:id)})
      end
    end
  end
end
