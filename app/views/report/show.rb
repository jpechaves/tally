# frozen_string_literal: true

module Tally
  module Views
    module Report
      class Show < Tally::View
        include Deps["repos.insight_repo", "repos.transaction_repo"]

        expose :months do
          transaction_repo.months
        end

        # The month asked for, or the latest complete one with rows (Insights.default_month).
        expose :month do |months, requested_month: nil|
          requested_month || Tally::Insights.default_month(months)
        end

        TREND_MONTHS = 6

        # Income and spending for the months up to this one, from the first with rows.
        expose :trend, decorate: false do |month|
          next [] unless month

          months = Tally::Insights.previous_months(month, TREND_MONTHS - 1) + [month]
          totals = Tally::Insights.monthly(insight_repo.rows(from: months.first, to: month), months)
          totals.drop_while { _1[:income_cents].zero? && _1[:spending_cents].zero? }
        end

        expose :report do |month|
          next unless month

          from = Tally::Insights.previous_months(month, Tally::Report::AVERAGE_MONTHS).first
          Tally::Report.new(insight_repo.rows(from:, to: month), month:)
        end
      end
    end
  end
end
