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
          back(response, id, result.failure)
        rescue Tally::Money::ParseError
          back(response, id, kind == "reimbursed" ? :invalid_reimbursed_amount : :invalid_adjusted_amount)
        end

        private

        def back(response, id, error)
          path = routes.path(:transaction, id:)
          response.redirect_to error ? "#{path}?#{URI.encode_www_form(error:)}" : path
        end
      end
    end
  end
end
