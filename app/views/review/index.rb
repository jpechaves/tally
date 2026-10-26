# frozen_string_literal: true

module Tally
  module Views
    module Review
      class Index < Tally::View
        include Deps["repos.category_repo", "repos.counterparty_repo", "repos.person_repo", "repos.transaction_repo"]

        # Groups per page: a group's rows always stay together.
        PER_PAGE = Tally::Pagination::PER_PAGE

        # Rows listed under a group, newest first; a payee may have hundreds, and rendering
        # them all made this page slow on the Pi (#174). The rest are a link away.
        ROWS_SHOWN = 10

        expose :saved

        expose :rows_shown, decorate: false do
          ROWS_SHOWN
        end

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

        # Who a Pix went to may be someone of the household (issue #164): marking them
        # makes its rows transfers, and they leave this list.
        expose :person_like, decorate: false do |groups|
          counterparty_repo.person_like(groups.filter_map(&:counterparty_id))
        end

        expose :people, decorate: false do
          person_repo.all
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
