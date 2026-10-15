# frozen_string_literal: true

module Tally
  module Views
    module Rules
      class Index < Tally::View
        include Deps["repos.category_repo", "repos.category_rule_repo"]

        ERRORS = {
          "invalid_field" => "Pick what to match and how.",
          "empty_pattern" => "A rule needs something to match.",
          "invalid_pattern" => "That is not a valid regular expression.",
          "category_not_found" => "Pick a category.",
          "invalid_amount" => "Amounts look like -50,00 (spending is negative)."
        }.freeze

        FIELDS = {
          "description" => "description",
          "counterparty_name" => "counterparty name",
          "counterparty_document" => "CNPJ / CPF",
          "bank_category" => "bank's category",
          "kind" => "kind"
        }.freeze

        OPERATORS = {"contains" => "contains", "starts_with" => "starts with", "equals" => "is", "regex" => "matches regex"}.freeze

        private_expose :error_code

        expose :error_message do |error_code|
          ERRORS.fetch(error_code.to_s, error_code)
        end

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
