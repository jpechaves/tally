# frozen_string_literal: true

module Tally
  module Operations
    # Adds a rule you wrote on the rules page, then categorizes every row that isn't
    # manual again, so past rows follow the rules as they are now.
    class SaveRule < Tally::Operation
      include Deps["repos.category_repo", "repos.category_rule_repo", "operations.categorize"]

      FIELDS = %w[description counterparty_name counterparty_document bank_category kind].freeze
      OPERATORS = %w[contains starts_with equals regex].freeze

      # @return [Integer] the new rule's id
      def call(field:, operator:, pattern:, category_id:, priority: 100, amount_min_cents: nil, amount_max_cents: nil)
        pattern = pattern.to_s.strip
        step Failure(:invalid_field) unless FIELDS.include?(field) && OPERATORS.include?(operator)
        step Failure(:empty_pattern) if pattern.empty?
        step Failure(:invalid_pattern) if operator == "regex" && Categorizer.regex(pattern).nil?
        step Failure(:category_not_found) unless category_repo.kinds.key?(category_id)

        transaction do
          id = category_rule_repo.create(field:, operator:, pattern:, category_id:, priority:, amount_min_cents:,
            amount_max_cents:, origin: "manual")
          categorize.()
          id
        end
      end
    end
  end
end
