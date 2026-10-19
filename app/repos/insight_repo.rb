# frozen_string_literal: true

module Tally
  module Repos
    # The rows behind the report, the cut suggestions and the installment calendar, as
    # plain hashes with their category, parent category and counterparty. Transfers and
    # rows a re-import flagged as missing are left out, and so are accounts in another
    # currency (Conta Global, in USD): every figure here is in reais.
    #
    # A row's amount_cents is what it counts as after your adjustment (Tally::Adjustments):
    # canceled rows, fully reimbursed ones and refunds counted inside a purchase are left
    # out, and the statement's own amount is kept as original_cents.
    #
    # Rows dated after today (installments on a future bill that is already exported) are
    # committed, not spent yet, so #rows leaves them out unless asked for them.
    class InsightRepo < Tally::DB::Repo
      # @param from [String] "YYYY-MM", first month included
      # @param to [String] "YYYY-MM", last month included
      # @param through [Date, nil] the last day included; nil includes rows dated later too
      # @param account_id [Integer, nil] one account's rows instead, in its own currency (the
      #   account's report)
      # @param without [Array<Integer>] ids of rows to leave out (the report hiding trips)
      def rows(from:, to:, through: Date.today, account_id: nil, without: [])
        last = [("#{to}-31"), through&.iso8601].compact.min
        scope(account_id).where(Sequel[:transactions][:occurred_on] => "#{from}-01"..last)
          .exclude(Sequel[:transactions][:id] => without).all
      end

      # A trip's rows (Tally::Trip), in every currency: bought between its dates (the purchase
      # date of an installment), or among `ids`, whatever their date.
      def trip_rows(starts_on:, ends_on:, ids: [])
        bought = Sequel.function(:coalesce, Sequel[:transactions][:purchased_on], Sequel[:transactions][:occurred_on])
        scope(currency: nil).where(Sequel.|({bought => starts_on..ends_on}, {Sequel[:transactions][:id] => ids})).all
      end

      def installment_rows
        scope.exclude(Sequel[:transactions][:installment_total] => nil)
          .left_join(:card_statements, id: Sequel[:transactions][:card_statement_id])
          .select_append(Sequel[:card_statements][:due_on].as(:bill_due_on))
          .all
      end

      def dismissed_keys = dismissed_suggestions.dataset.select_map(:key)

      def dismissed = dismissed_suggestions.dataset.order(Sequel.desc(:id)).all

      def dismiss(key:, title:)
        dismissed_suggestions.dataset.insert_conflict(target: :key).insert(key:, title:)
      end

      def restore(id) = dismissed_suggestions.dataset.where(id:).delete

      private

      # @param currency [String, nil] nil for every currency
      def scope(account_id = nil, currency: Tally::Money::DEFAULT_CURRENCY)
        dataset = Tally::Adjustments.join(transactions.dataset)
          .exclude(Sequel[:transactions][:kind] => "transfer")
          .where(Sequel[:transactions][:missing_since_import_id] => nil)
          .join(:accounts, id: Sequel[:transactions][:account_id])
        if account_id then dataset = dataset.where(Sequel[:transactions][:account_id] => account_id)
        elsif currency then dataset = dataset.where(Sequel[:accounts][:currency] => currency)
        end
        dataset
          .left_join(:counterparties, id: Sequel[:transactions][:counterparty_id])
          .left_join(:categories, id: Sequel[:transactions][:category_id])
          .left_join(Sequel[:categories].as(:parents), id: Sequel[:categories][:parent_id])
          .select(
            *%i[id account_id occurred_on purchased_on kind description counterparty_id category_id
              installment_number installment_total purchase_key].map { Sequel[:transactions][_1] },
            Sequel[:accounts][:name].as(:account_name),
            Sequel[:accounts][:currency],
            Tally::DB::Repo.counterparty_label.as(:counterparty_name),
            Sequel[:categories][:name].as(:category_name),
            Sequel[:categories][:parent_id],
            Sequel[:parents][:name].as(:parent_name),
            Sequel[:categories][:nature],
            Sequel[:categories][:max_cut_pct]
          )
          .select_append(
            Tally::Adjustments.counted_amount.as(:amount_cents),
            Sequel[:transactions][:amount_cents].as(:original_cents)
          )
          .exclude(Tally::Adjustments.counted_amount => 0)
          .order(Sequel[:transactions][:occurred_on], Sequel[:transactions][:id])
      end
    end
  end
end
