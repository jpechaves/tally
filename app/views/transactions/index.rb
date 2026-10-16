# frozen_string_literal: true

module Tally
  module Views
    module Transactions
      class Index < Tally::View
        include Deps["repos.account_repo", "repos.category_repo", "repos.transaction_repo"]

        PER_PAGE = Tally::Pagination::PER_PAGE

        expose :filter, decorate: false

        expose :accounts do
          account_repo.all
        end

        expose :months do
          transaction_repo.months
        end

        expose :categories do
          category_repo.tree
        end

        # Rows and net of everything the filters match, not just this page.
        expose :totals, decorate: false do |filter|
          transaction_repo.totals(filter)
        end

        expose :pagination, decorate: false do |totals, page:|
          Tally::Pagination.page(page, total: totals[:rows], per_page: PER_PAGE)
        end

        expose :rows do |filter, pagination|
          transaction_repo.list(filter, limit: pagination.limit, offset: pagination.offset)
        end
      end
    end
  end
end
