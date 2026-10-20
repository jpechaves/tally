# frozen_string_literal: true

module Tally
  module Actions
    module Transactions
      # A category of your own for the rows picked in the transactions table: one row from
      # its category cell, or the ticked rows at once. Like picking it on a row's page, it
      # is manual (imports and rules leave it alone) and makes no rule. Back to the same
      # filters and page.
      class Recategorize < Tally::Action
        include Deps["operations.assign_category"]

        def handle(request, response)
          params = request.params
          result = assign_category.(
            ids: Array(params[:ids]).map(&:to_s).grep(Tally::TransactionFilter::ID).map(&:to_i),
            category_id: params[:category_id].to_i
          )
          halt 422, t("errors.could_not_save", reason: result.failure) if result.failure?

          response.redirect_to Tally::TransactionFilter.parse(params).pages.(Tally::Pagination.param(params[:page]))
        end
      end
    end
  end
end
