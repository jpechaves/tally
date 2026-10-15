# frozen_string_literal: true

module Tally
  module Views
    module Accounts
      class Index < Tally::View
        include Deps["settings", "repos.account_repo", "repos.bill_check_repo"]

        expose :accounts do
          account_repo.with_balances
        end

        expose :tolerance_cents do
          settings.pass_through_tolerance_cents
        end

        expose :checks do
          bill_check_repo.all
        end
      end
    end
  end
end
