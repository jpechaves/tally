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
          # The page that sent you to this list, for the way back (issue #87).
          response[:return_to] = back_param(request.params[:back])
        end
      end
    end
  end
end
