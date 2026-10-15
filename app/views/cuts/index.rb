# frozen_string_literal: true

module Tally
  module Views
    module Cuts
      class Index < Tally::View
        include Deps["repos.insight_repo", "repos.transaction_repo"]

        expose :months do
          transaction_repo.months
        end

        expose :month do |months, requested_month: nil|
          requested_month || months.first
        end

        expose :suggestions do |month|
          next [] unless month

          from = Tally::Insights.previous_months(month, 3).first
          Tally::Cuts.new(insight_repo.rows(from:, to: month), month:, dismissed: insight_repo.dismissed_keys).suggestions
        end

        expose :total_cents do |suggestions|
          suggestions.sum(&:monthly_cents)
        end

        expose :dismissed do
          insight_repo.dismissed
        end
      end
    end
  end
end
