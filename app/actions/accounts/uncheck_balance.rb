# frozen_string_literal: true

module Tally
  module Actions
    module Accounts
      class UncheckBalance < Tally::Action
        include Deps["repos.balance_check_repo"]

        def handle(request, response)
          balance_check_repo.delete(request.params[:id].to_i)
          response.redirect_to "/accounts#balances"
        end
      end
    end
  end
end
