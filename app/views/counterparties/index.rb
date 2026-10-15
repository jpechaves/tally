# frozen_string_literal: true

module Tally
  module Views
    module Counterparties
      class Index < Tally::View
        include Deps["repos.counterparty_repo"]

        PER_PAGE = Transactions::Index::PER_PAGE

        expose :search

        # How many the search finds, across all pages.
        expose :count, decorate: false do |search|
          counterparty_repo.count(search:)
        end

        expose :pages, decorate: false do |count|
          [(count + PER_PAGE - 1) / PER_PAGE, 1].max
        end

        # The page asked for, kept within the pages there are.
        expose :current_page, decorate: false do |pages, page:|
          page.clamp(1, pages)
        end

        expose :counterparties do |search, current_page|
          counterparty_repo.with_totals(search:, limit: PER_PAGE, offset: (current_page - 1) * PER_PAGE)
        end

        # The link to another page, keeping the search.
        expose :page_path, decorate: false do |search|
          lambda do |number|
            "/counterparties?#{URI.encode_www_form({q: (search unless search.empty?), page: number}.compact)}"
          end
        end
      end
    end
  end
end
