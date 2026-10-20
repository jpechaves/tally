# frozen_string_literal: true

module Tally
  module Actions
    module Accounts
      # One account's own report, in its currency (Views::Accounts::Report).
      class Report < Tally::Action
        include Deps["repos.account_repo"]

        def handle(request, response)
          response[:account] = found(account_repo, request)
          response[:requested_month] = month_param(request.params[:month])
        end
      end
    end
  end
end
