# frozen_string_literal: true

module Tally
  module Actions
    module Installments
      class Index < Tally::Action
        def handle(request, response)
          response[:card_id] = Tally::TransactionFilter.parse(request.params).account
        end
      end
    end
  end
end
