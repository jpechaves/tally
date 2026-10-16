# frozen_string_literal: true

module Tally
  module Views
    module Review
      class Index < Tally::View
        include Deps["repos.category_repo", "repos.transaction_repo"]

        # Groups per page: a group's rows always stay together.
        PER_PAGE = Tally::Pagination::PER_PAGE

        expose :saved

        # Every group, so the counts at the top cover all pages.
        expose :all_groups, decorate: false do
          Tally::Review.groups(transaction_repo.to_review)
        end

        # Saving the last group of the last page lands on the page before it.
        expose :pagination, decorate: false do |all_groups, page:|
          Tally::Pagination.page(page, total: all_groups.size, per_page: PER_PAGE)
        end

        expose :groups do |all_groups, pagination|
          pagination.slice(all_groups)
        end

        expose :categories do
          category_repo.tree
        end

        expose :uncategorized do |all_groups|
          all_groups.sum { |group| group.rows.count { _1[:category_source] == "none" } }
        end

        expose :suggested do |all_groups|
          all_groups.sum { |group| group.rows.count { _1[:category_source] == "bank" } }
        end

        expose :group_count, decorate: false do |all_groups|
          all_groups.size
        end

        expose :page_path, decorate: false do
          Tally::Pagination.path("/review")
        end
      end
    end
  end
end
