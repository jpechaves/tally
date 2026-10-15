# frozen_string_literal: true

module Tally
  module Actions
    module Transactions
      class Show < Tally::Action
        include Deps["repos.transaction_repo"]

        def handle(request, response)
          row = transaction_repo.list(id: request.params[:id].to_i).first
          halt 404 unless row

          response[:row] = row
        end
      end
    end
  end
end
