# frozen_string_literal: true

module Tally
  module Actions
    module Transactions
      # Marks one row canceled, reimbursed or with another amount (Operations::AdjustTransaction).
      class Adjust < Tally::Action
        include Deps["routes", "operations.adjust_transaction"]

        def handle(request, response)
          id = request.params[:id].to_i
          kind = request.params[:kind].to_s
          refund_id = request.params[:refund_id].to_s[/\A\d+\z/]&.to_i
          amount = request.params[:amount].to_s.strip
          amount = amount.empty? || refund_id ? nil : parse_amount(amount)

          result = adjust_transaction.(id:, kind:, amount:, refund_id:, note: request.params[:note])
          halt 404 if result.failure == :not_found
          back(request, response, id, result.failure)
        rescue Tally::Money::ParseError
          back(request, response, id, kind == "reimbursed" ? :invalid_reimbursed_amount : :invalid_adjusted_amount)
        end

        private

        # Back to the row's page, with the error, if any, and the page that page goes back to.
        def back(request, response, id, error)
          response.redirect_to path_with(routes.path(:transaction, id:), error:, back: back_param(request.params[:back]))
        end
      end
    end
  end
end
