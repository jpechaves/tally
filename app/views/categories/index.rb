# frozen_string_literal: true

module Tally
  module Views
    module Categories
      class Index < Tally::View
        include Deps["repos.category_repo"]

        # The error the last form sent back, if any (config/i18n, "errors").
        expose :error_code, decorate: false

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
