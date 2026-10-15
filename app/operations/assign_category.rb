# frozen_string_literal: true

module Tally
  module Operations
    # Your choice of category for some rows, from the review list or a transaction's page.
    #
    # - Just these rows: they become manual, and imports and rules leave them alone.
    # - Always (a group in the review list): the counterparty gets it as its default, or,
    #   for card rows with no counterparty, a learned rule matches the description. Every
    #   past row that isn't manual is then categorized again, so the choice covers them
    #   and future imports.
    class AssignCategory < Tally::Operation
      include Deps[
        "repos.category_repo",
        "repos.category_rule_repo",
        "repos.counterparty_repo",
        "repos.transaction_repo",
        "operations.categorize"
      ]

      LEARNED_PRIORITY = 50

      # @param ids [Array<Integer>] the rows you chose for
      # @param counterparty_id [Integer, nil] with always: the counterparty they share
      # @param pattern [String, nil] with always and no counterparty: the description rule
      # @return [Integer] how many rows changed
      def call(ids:, category_id:, always: false, counterparty_id: nil, pattern: nil)
        category = category_repo.find(category_id)
        step Failure(:category_not_found) unless category && category[:archived_at].nil?
        step Failure(:no_rows) if ids.empty?

        transaction do
          if always && counterparty_id
            counterparty_repo.set_default_category(counterparty_id, category_id)
            categorize.(ids: transaction_repo.ids_for_counterparty(counterparty_id))
          elsif always && pattern
            learn(pattern, category_id)
            categorize.()
          end

          # Rows the default or rule could not cover (an expense category picked for money
          # in, say) still get what you chose.
          left = transaction_repo.rows(ids).reject { _1[:category_id] == category_id && _1[:category_source] == "rule" }
          transaction_repo.set_category(left.map { _1[:id] }, category_id:, category_source: "manual")
          category_rule_repo.recount_hits
          ids.size
        end
      end

      private

      def learn(pattern, category_id)
        step Failure(:invalid_pattern) unless Categorizer.regex(pattern)

        existing = category_rule_repo.find_by_match(field: "description", operator: "regex", pattern:)
        if existing
          category_rule_repo.update(existing[:id], category_id:, disabled_at: nil)
        else
          category_rule_repo.create(field: "description", operator: "regex", pattern:, category_id:,
            origin: "learned", priority: LEARNED_PRIORITY)
        end
      end
    end
  end
end
