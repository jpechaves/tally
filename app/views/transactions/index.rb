# frozen_string_literal: true

module Tally
  module Views
    module Transactions
      class Index < Tally::View
        include Deps["repos.account_repo", "repos.transaction_repo"]

        PER_PAGE = 100

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

        expose :pages, decorate: false do |totals|
          [(totals[:rows] + PER_PAGE - 1) / PER_PAGE, 1].max
        end

        # The page asked for, kept within the pages there are.
        expose :current_page, decorate: false do |pages, page:|
          page.clamp(1, pages)
        end

        expose :rows do |account_id, month, current_page|
          transaction_repo.list(account_id:, month:, limit: PER_PAGE, offset: (current_page - 1) * PER_PAGE)
        end

        # The link to another page, keeping the filters.
        expose :page_path, decorate: false do |account_id, month|
          lambda do |number|
            query = {account: account_id, month:, page: number}.compact.map { |key, value| "#{key}=#{value}" }.join("&")
            "/transactions?#{query}"
          end
        end
      end
    end
  end
end
