# frozen_string_literal: true

module Tally
  module Views
    module Accounts
      # Where one account's money went, in its own currency: Conta Global's dollars never
      # mix with the main report's reais (issue #22). Spending by category and by month,
      # top payees, and what the money cost in reais through its top-ups.
      class Report < Tally::View
        include Deps["repos.insight_repo", "repos.transaction_repo"]

        MONTHS = 12

        expose :account, decorate: false

        expose :months do |account|
          transaction_repo.months(account_id: account.id)
        end

        expose :month do |months, requested_month: nil|
          requested_month || Tally::Insights.default_month(months)
        end

        expose :report do |account, month|
          next unless month

          from = Tally::Insights.previous_months(month, Tally::Report::AVERAGE_MONTHS).first
          Tally::Report.new(insight_repo.rows(from:, to: month, account_id: account.id), month:)
        end

        # Income and spending for the twelve months up to this one, from the first with rows.
        expose :by_month, decorate: false do |account, month|
          next [] unless month

          months = Tally::Insights.previous_months(month, MONTHS - 1) + [month]
          totals = Tally::Insights.monthly(insight_repo.rows(from: months.first, to: month, account_id: account.id), months)
          totals.drop_while { _1[:income_cents].zero? && _1[:spending_cents].zero? }
        end

        # Every top-up of a foreign-currency account up to the end of the month; the page
        # lists the month's.
        expose :top_ups, decorate: false do |account, month|
          next [] unless month && account.currency != Tally::Money::DEFAULT_CURRENCY

          transaction_repo.top_ups(account.id, through: "#{month}-31")
        end

        expose :month_top_ups, decorate: false do |top_ups, month|
          top_ups.select { Tally::Insights.month_of(_1) == month }
        end

        # What a unit of this account's money cost in reais, over every top-up so far.
        expose :average_cost, decorate: false do |top_ups|
          Tally::TopUps.average(top_ups)
        end
      end
    end
  end
end
