# frozen_string_literal: true

module Tally
  module Views
    module Transactions
      class Show < Tally::View
        include Deps["repos.category_repo"]

        expose :row

        expose :categories do
          category_repo.tree
        end
      end
    end
  end
end
