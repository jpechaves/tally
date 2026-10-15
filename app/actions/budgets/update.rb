# frozen_string_literal: true

module Tally
  module Actions
    module Budgets
      # Changes one category's limit from a month on.
      class Update < Tally::Action
        include Deps["routes", "repos.plan_repo", "repos.category_repo"]

        def handle(request, response)
          month = request.params[:month].to_s[/\A\d{4}-(0[1-9]|1[0-2])\z/]
          category = category_repo.find(request.params[:category_id].to_i)
          return back(response, month, "invalid_category") unless month && category && category[:kind] == "expense"

          amount = Tally::Money.parse(request.params[:amount].to_s, decimal: ",").cents
          return back(response, month, "invalid_amount") if amount.negative?

          plan_repo.set_budget(category[:id], month, amount)
          back(response, month)
        rescue Tally::Money::ParseError
          back(response, month, "invalid_amount")
        end

        private

        def back(response, month, error = nil)
          query = {month:, error:}.compact
          path = routes.path(:budgets)
          response.redirect_to query.empty? ? path : "#{path}?#{URI.encode_www_form(query)}"
        end
      end
    end
  end
end
