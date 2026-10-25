# frozen_string_literal: true

module Tally
  module Actions
    module Accounts
      # The balance the bank showed for an account on a day (Tally::Balances).
      class CheckBalance < Tally::Action
        include Deps["repos.account_repo", "repos.balance_check_repo"]

        DATE = /\A\d{4}-\d{2}-\d{2}\z/

        def handle(request, response)
          params = request.params
          account = account_repo.find(params[:account_id].to_i) || halt(422, t("errors.invalid_balance_check"))
          checked_on = Date.iso8601(params[:checked_on].to_s[DATE].to_s).iso8601
          balance_check_repo.add(account_id: account.id, checked_on:, balance_cents: parse_amount(params[:balance]).cents)
          response.redirect_to "/accounts#balances"
        rescue Date::Error, Tally::Money::ParseError
          halt 422, t("errors.invalid_balance_check")
        end
      end
    end
  end
end
