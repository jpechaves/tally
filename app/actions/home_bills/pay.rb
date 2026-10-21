# frozen_string_literal: true

module Tally
  module Actions
    module HomeBills
      # Marks a month paid: by an imported row (transaction_id), paid by its account's owner, or
      # by hand with the day, the amount and who of the household paid (person_id, you if none).
      class Pay < Tally::Action
        include Deps["repos.home_bill_repo", "repos.person_repo"]

        DATE = /\A\d{4}-\d{2}-\d{2}\z/

        def handle(request, response)
          bill = found(home_bill_repo, request)
          params = request.params
          month = month_param(params[:month]) || halt(422, t("errors.invalid_payment"))
          payment = params[:transaction_id] ? linked(params[:transaction_id]) : by_hand(params)

          home_bill_repo.pay(bill[:id], month, **payment)
          response.redirect_to "/home-bills/#{bill[:id]}"
        end

        private

        def linked(transaction_id) = home_bill_repo.link(transaction_id.to_i) || halt(404)

        def by_hand(params)
          paid_on = Date.iso8601(params[:paid_on].to_s[DATE].to_s).iso8601
          amount_cents = parse_amount(params[:amount]).cents
          raise ArgumentError unless amount_cents.positive?

          {paid_on:, amount_cents:, paid_by: payer(params[:person_id]).name}
        rescue ArgumentError, Tally::Money::ParseError
          halt 422, t("errors.invalid_payment")
        end

        def payer(id) = id ? person_repo.find(id.to_i) || raise(ArgumentError) : person_repo.first
      end
    end
  end
end
