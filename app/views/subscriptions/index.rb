# frozen_string_literal: true

module Tally
  module Views
    module Subscriptions
      # Charges that repeat every month (Tally::Subscriptions), up to the latest month that
      # is over, from two years of history.
      class Index < Tally::View
        include Deps["repos.insight_repo", "repos.transaction_repo", "repos.subscription_repo"]

        HISTORY_MONTHS = 24

        expose :month do
          Tally::Insights.default_month(transaction_repo.months)
        end

        expose :subscriptions, decorate: false do |month|
          next unless month

          from = Tally::Insights.previous_months(month, HISTORY_MONTHS - 1).first
          Tally::Subscriptions.new(insight_repo.rows(from:, to: month), month:,
            dismissed: subscription_repo.keys("dismissed"), marked: subscription_repo.keys("marked"))
        end

        expose :marks, decorate: false do
          subscription_repo.marks
        end
      end
    end
  end
end
