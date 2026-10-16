# frozen_string_literal: true

module Tally
  module Views
    module Transactions
      class Index < Tally::View
        include Deps["repos.account_repo", "repos.transaction_repo"]

        PER_PAGE = Tally::Pagination::PER_PAGE

        expose :account_id
        expose :month

        expose :accounts do
          account_repo.all
        end

        expose :months do
          transaction_repo.months
        end

        # Rows and net of everything the filters match, not just this page.
        expose :totals, decorate: false do |account_id, month|
          transaction_repo.totals(account_id:, month:)
        end

        expose :pagination, decorate: false do |totals, page:|
          Tally::Pagination.page(page, total: totals[:rows], per_page: PER_PAGE)
        end

        expose :rows do |account_id, month, pagination|
          transaction_repo.list(account_id:, month:, limit: pagination.limit, offset: pagination.offset)
        end

        expose :page_path, decorate: false do |account_id, month|
          Tally::Pagination.path("/transactions", account: account_id, month:)
        end
      end
    end
  end
end
