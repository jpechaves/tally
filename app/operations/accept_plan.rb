# frozen_string_literal: true

module Tally
  module Operations
    # Accepts a draft plan with your edits to its limits. It becomes the active plan and
    # writes the budgets from its first month.
    class AcceptPlan < Tally::Operation
      include Deps["repos.plan_repo"]

      # @param proposed [Hash{Integer => Integer}] category id => monthly limit in cents
      def call(id:, proposed: {})
        plan = plan_repo.find(id)
        step Failure(:not_found) unless plan
        step Failure(:not_a_draft) unless plan[:status] == "draft"
        step Failure(:invalid_amount) unless proposed.values.all? { _1.is_a?(Integer) && _1 >= 0 }

        known = plan_repo.lines(id).map { _1[:category_id] }
        transaction { plan_repo.accept(id, proposed: proposed.slice(*known)) }
        id
      end
    end
  end
end
