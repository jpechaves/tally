# frozen_string_literal: true

module Tally
  module Views
    module Categories
      class Index < Tally::View
        include Deps["repos.category_repo"]

        ERRORS = {
          "empty_name" => "A category needs a name.",
          "name_taken" => "There is already a category with that name there.",
          "invalid_parent" => "Categories go one level deep: pick a top-level parent.",
          "invalid_kind" => "Pick expense or income.",
          "invalid_nature" => "Pick fixed, essential or discretionary.",
          "invalid_max_cut" => "The maximum cut is a percentage from 0 to 100."
        }.freeze

        private_expose :error_code

        expose :error_message do |error_code|
          ERRORS.fetch(error_code.to_s, error_code)
        end

        expose :categories do
          category_repo.tree(include_archived: true)
        end

        expose :parents do |categories|
          categories.reject { _1[:parent_id] || _1[:archived_at] }
        end

        expose :natures do
          Tally::Categories::NATURES
        end
      end
    end
  end
end
