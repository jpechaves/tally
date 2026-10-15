# frozen_string_literal: true

module Tally
  module Views
    module Transactions
      class Index < Tally::View
        include Deps["repos.account_repo", "repos.transaction_repo"]

        expose :account_id
        expose :month

        expose :accounts do
          account_repo.all
        end

        expose :months do
          transaction_repo.months
        end

        expose :rows do |account_id, month|
          transaction_repo.list(account_id:, month:)
        end

        expose :total_cents do |rows|
          rows.sum { _1[:amount_cents] }
        end
      end
    end
  end
end
