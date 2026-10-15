# frozen_string_literal: true

module Tally
  module Views
    module Rules
      class Index < Tally::View
        include Deps["repos.category_repo", "repos.category_rule_repo"]

        FIELDS = %w[description counterparty_name counterparty_document bank_category kind].freeze

        OPERATORS = %w[contains starts_with equals regex].freeze

        # The error the last form sent back, if any (config/i18n, "errors").
        expose :error_code, decorate: false

        expose :rules do
          category_rule_repo.list
        end

        expose :categories do
          category_repo.tree
        end

        expose :fields, decorate: false do
          FIELDS
        end

        expose :operators, decorate: false do
          OPERATORS
        end
      end
    end
  end
end
