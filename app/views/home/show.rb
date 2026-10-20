# frozen_string_literal: true

module Tally
  module Views
    module Home
      # The dashboard: the latest complete month at a glance, the last year's income
      # against spending, and where the money went.
      class Show < Tally::View
        include Deps["repos.insight_repo", "repos.transaction_repo"]
        include PersonSwitch

        TREND_MONTHS = 12
        TOP_CATEGORIES = 6

        expose :month do
          Tally::Insights.default_month(transaction_repo.months)
        end

        expose :report do |month, person|
          next unless month

          from = Tally::Insights.previous_months(month, Tally::Report::AVERAGE_MONTHS).first
          Tally::Report.new(insight_repo.rows(from:, to: month, person: person&.id), month:)
        end

        # Income and spending per month up to `month`, from the first month with rows.
        expose :trend, decorate: false do |month, person|
          next [] unless month

          months = Tally::Insights.previous_months(month, TREND_MONTHS - 1) + [month]
          totals = Tally::Insights.monthly(insight_repo.rows(from: months.first, to: month, person: person&.id), months)
          totals.drop_while { _1[:income_cents].zero? && _1[:spending_cents].zero? }
        end

        expose :top_categories, decorate: false do |report|
          report ? report.categories.first(TOP_CATEGORIES) : []
        end
      end
    end
  end
end
