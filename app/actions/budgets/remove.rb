# frozen_string_literal: true

module Tally
  module Actions
    module Budgets
      # Removes one category's budget ("category_id"), or every budget ("all"), from a
      # month on.
      class Remove < Tally::Action
        include Deps["routes", "repos.category_repo", "operations.remove_budgets"]
        include Back

        def handle(request, response)
          month = month_param(request.params[:month])
          return back(response, month, "month_and_category") unless month

          if request.params[:all] == "1"
            remove_budgets.(month:)
          else
            category = category_repo.find(request.params[:category_id].to_i)
            return back(response, month, "month_and_category") unless category

            remove_budgets.(month:, category_id: category[:id])
          end
          back(response, month)
        end
      end
    end
  end
end
