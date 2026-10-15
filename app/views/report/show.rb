# frozen_string_literal: true

module Tally
  module Views
    module Report
      class Show < Tally::View
        include Deps["repos.insight_repo", "repos.transaction_repo"]

        expose :months do
          transaction_repo.months
        end

        # The month asked for, or the latest one with rows.
        expose :month do |months, requested_month: nil|
          requested_month || months.first
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
