# frozen_string_literal: true

module Tally
  module Operations
    # Runs the categorizer (Tally::Categorizer) over rows and saves what changed. Manual
    # categories are never touched. Runs after each import, after "This is me", and after
    # any change to rules or counterparty defaults, so past rows follow your latest
    # choices.
    class Categorize < Tally::Operation
      include Deps[
        "repos.category_repo",
        "repos.category_rule_repo",
        "repos.transaction_repo",
        "operations.seed_categories"
      ]

      # @param ids [Array<Integer>, nil] the rows to look at; nil for all of them
      # @return [Integer] how many rows changed
      def call(ids: nil)
        seed_categories.() if category_repo.empty?
        hint_ids = category_repo.ids_by_name(Categories::BANK_HINTS.values.flat_map { Categories.names(_1) })
        categorizer = Categorizer.new(
          rules: category_rule_repo.active,
          categories: category_repo.kinds,
          bank_hints: Categories::BANK_HINTS.transform_values { |name| Categories.names(name).filter_map { hint_ids[_1] }.first }.compact
        )

        transaction do
          changed = transaction_repo.for_categorizing(ids:).count do |row|
            decision = categorizer.(row)
            next false if decision.category_id == row[:category_id] && decision.source == row[:category_source] &&
              decision.rule_id == row[:category_rule_id]

            transaction_repo.set_category(row[:id], category_id: decision.category_id,
              category_source: decision.source, category_rule_id: decision.rule_id)
            true
          end
          category_rule_repo.recount_hits
          changed
        end
      end
    end
  end
end
