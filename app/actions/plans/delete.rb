# frozen_string_literal: true

module Tally
  module Actions
    module Plans
      # Deletes a plan; "remove_budgets" also removes the budgets it wrote.
      class Delete < Tally::Action
        include Deps["routes", "operations.delete_plan"]

        def handle(request, response)
          remove_budgets = request.params[:remove_budgets] == "1"
          result = delete_plan.call(id: request.params[:id].to_i, remove_budgets:)
          halt 404 if result.failure?

          notice = if result.value!.zero? then "plan_deleted"
          elsif remove_budgets then "plan_deleted_with_budgets"
          else "plan_deleted_kept_budgets"
          end
          response.redirect_to "#{routes.path(:plans)}?notice=#{notice}"
        end
      end
    end
  end
end
