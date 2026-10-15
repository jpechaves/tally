# frozen_string_literal: true

module Tally
  module Views
    module Review
      class Index < Tally::View
        include Deps["repos.category_repo", "repos.transaction_repo"]

        expose :saved

        expose :groups do
          Tally::Review.groups(transaction_repo.to_review)
        end

        expose :categories do
          category_repo.tree
        end

        expose :uncategorized do |groups|
          groups.sum { |group| group.rows.count { _1[:category_source] == "none" } }
        end

        expose :suggested do |groups|
          groups.sum { |group| group.rows.count { _1[:category_source] == "bank" } }
        end
      end
    end
  end
end
