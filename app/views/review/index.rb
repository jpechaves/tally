# frozen_string_literal: true

module Tally
  module Views
    module Review
      class Index < Tally::View
        include Deps["repos.category_repo", "repos.transaction_repo"]

        # Groups per page, as many as /transactions has rows.
        PER_PAGE = Transactions::Index::PER_PAGE

        expose :saved

        # Every group, so the counts at the top cover all pages.
        expose :all_groups, decorate: false do
          Tally::Review.groups(transaction_repo.to_review)
        end

        expose :pages, decorate: false do |all_groups|
          [(all_groups.size + PER_PAGE - 1) / PER_PAGE, 1].max
        end

        # The page asked for, kept within the pages there are: saving the last group of
        # the last page lands on the page before it.
        expose :current_page, decorate: false do |pages, page:|
          page.clamp(1, pages)
        end

        expose :groups do |all_groups, current_page|
          all_groups.slice((current_page - 1) * PER_PAGE, PER_PAGE) || []
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
          ->(number) { "/review?page=#{number}" }
        end
      end
    end
  end
end
