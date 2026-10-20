# frozen_string_literal: true

module Tally
  module Actions
    module Transactions
      # Your category and memo for one row. A category you pick is manual: imports and
      # rules never change it. "Automatic" hands the row back to the rules.
      class Update < Tally::Action
        include Deps["routes", "repos.transaction_repo", "operations.assign_category", "operations.categorize"]

        def handle(request, response)
          id = request.params[:id].to_i
          row = transaction_repo.row(id)
          halt 404 unless row

          memo = request.params[:memo].to_s.strip
          transaction_repo.update(id, memo: memo.empty? ? nil : memo)

          category_id = request.params[:category_id].to_s[/\A\d+\z/]&.to_i
          if category_id
            result = assign_category.(ids: [id], category_id:)
            halt 422, t("errors.could_not_save", reason: result.failure) if result.failure?
          elsif row[:category_source] == "manual"
            transaction_repo.set_category(id, category_id: nil, category_source: "none")
            categorize.(ids: [id])
          end

          response.redirect_to path_with(routes.path(:transaction, id:), back: back_param(request.params[:back]))
        end
      end
    end
  end
end
