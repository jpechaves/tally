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
          halt 422, "Pick a month and a category" unless month && category && category[:kind] == "expense"

          amount = Tally::Money.parse(request.params[:amount].to_s, decimal: ",").cents
          halt 422, "A limit can't be negative" if amount.negative?

          plan_repo.set_budget(category[:id], month, amount)
          response.redirect_to "#{routes.path(:budgets)}?month=#{month}"
        rescue Tally::Money::ParseError => e
          halt 422, e.message
        end
      end
    end
  end
end
