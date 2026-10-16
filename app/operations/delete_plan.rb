# frozen_string_literal: true

module Tally
  module Operations
    # Deletes a savings plan, in any state. See PlanRepo#delete for its budgets.
    class DeletePlan < Tally::Operation
      include Deps["repos.plan_repo"]

      # @return [Integer] how many budgets the plan had written
      def call(id:, remove_budgets:)
        step Failure(:not_found) unless plan_repo.find(id)

        transaction { plan_repo.delete(id, remove_budgets:) }
      end
    end
  end
end
