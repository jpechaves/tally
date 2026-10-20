# frozen_string_literal: true

module Tally
  module Views
    module Counterparties
      class Index < Tally::View
        include Deps["repos.counterparty_repo", "repos.person_repo"]

        PER_PAGE = Tally::Pagination::PER_PAGE

        expose :search

        # Counted across all pages.
        expose :pagination, decorate: false do |search, page:|
          Tally::Pagination.page(page, total: counterparty_repo.count(search:), per_page: PER_PAGE)
        end

        expose :counterparties do |search, pagination|
          counterparty_repo.with_totals(search:, limit: pagination.limit, offset: pagination.offset)
        end

        # The household (issue #21): with one person, a "This is me" button; with more, a
        # choice of who it is.
        expose :people, decorate: false do
          person_repo.all
        end

        # The link to another page, keeping the search.
        expose :page_path, decorate: false do |search|
          Tally::Pagination.path("/counterparties", q: search)
        end
      end
    end
  end
end
