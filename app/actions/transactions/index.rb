# frozen_string_literal: true

module Tally
  module Actions
    module Transactions
      class Index < Tally::Action
        def handle(request, response)
          response[:filter] = Tally::TransactionFilter.parse(request.params)
          response[:page] = Tally::Pagination.param(request.params[:page])
        end
      end
    end
  end
end
