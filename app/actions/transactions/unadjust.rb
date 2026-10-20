# frozen_string_literal: true

module Tally
  module Actions
    module Transactions
      # Drops a row's adjustment: it counts as the statement says again.
      class Unadjust < Tally::Action
        include Deps["routes", "repos.transaction_repo"]

        def handle(request, response)
          id = request.params[:id].to_i
          halt 404 unless transaction_repo.row(id)

          transaction_repo.remove_adjustment(id)
          response.redirect_to path_with(routes.path(:transaction, id:), back: back_param(request.params[:back]))
        end
      end
    end
  end
end
