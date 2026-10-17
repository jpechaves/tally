# frozen_string_literal: true

module Tally
  module Actions
    module Budgets
      # Changes one category's limit from a month on.
      class Update < Tally::Action
        include Deps["routes", "repos.plan_repo", "repos.category_repo"]
        include Back

        def handle(request, response)
          month = month_param(request.params[:month])
          category = category_repo.find(request.params[:category_id].to_i)
          return back(response, month, "month_and_category") unless month && category && category[:kind] == "expense"

          amount = parse_amount(request.params[:amount].to_s).cents
          return back(response, month, "invalid_limit") if amount.negative?

          plan_repo.set_budget(category[:id], month, amount)
          back(response, month)
        rescue Tally::Money::ParseError
          back(response, month, "invalid_limit")
        end
      end
    end
  end
end
