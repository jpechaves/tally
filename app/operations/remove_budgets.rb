# frozen_string_literal: true

module Tally
  module Operations
    # Removes one category's budget, or every budget, from a month on. Like editing a
    # limit, it leaves the months before alone.
    class RemoveBudgets < Tally::Operation
      include Deps["repos.plan_repo"]

      # @param month [String] "YYYY-MM"
      # @param category_id [Integer, nil] nil for every category
      def call(month:, category_id: nil)
        transaction do
          (category_id ? [category_id] : plan_repo.budgeted_category_ids).each { plan_repo.remove_budget(_1, month) }
        end
      end
    end
  end
end
