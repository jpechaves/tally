# frozen_string_literal: true

module Tally
  module Actions
    module Transactions
      class Index < Tally::Action
        def handle(request, response)
          response[:filter] = Tally::TransactionFilter.parse(request.params)
          response[:page] = Tally::Pagination.param(request.params[:page])
          # How many rows a change of category from the table just changed, and skipped.
          response[:changed] = request.params[:changed].to_s[/\A\d+\z/]&.to_i
          response[:skipped] = request.params[:skipped].to_s[/\A\d+\z/].to_i
        end
      end
    end
  end
end
