# frozen_string_literal: true

module Tally
  module Operations
    # Adds the starting categories and generic rules (Tally::Categories) that are not
    # there yet. Safe to run any time: it never changes or brings back anything you
    # edited, archived or switched off. Runs from config/db/seeds.rb, and on the first
    # categorization of a database that has no categories.
    #
    # New categories are named in the default locale (the DEFAULT_LOCALE setting). A
    # category already there under its name in the other locale counts as there.
    class SeedCategories < Tally::Operation
      include Deps["settings", "repos.category_repo", "repos.category_rule_repo"]

      # @return [Hash] how many categories and rules were added
      def call(locale: settings.default_locale)
        added = {categories: 0, rules: 0}

        transaction do
          Categories::EXPENSES.each do |parent, children|
            parent_id = ensure_category(added, locale, name: parent, kind: "expense")
            children.each do |name, nature|
              ensure_category(added, locale, name:, kind: "expense", parent_id:, nature:)
            end
          end

          Categories::INCOME.each do |parent, children|
            parent_id = ensure_category(added, locale, name: parent, kind: "income")
            children.each { ensure_category(added, locale, name: _1, kind: "income", parent_id:) }
          end

          Categories::RULES.each do |field, operator, pattern, category, options = {}|
            next if category_rule_repo.find_by_match(field:, operator:, pattern:)

            category_id = category_repo.id_by_name(Categories.names(category)) or raise ArgumentError, "no category #{category}"
            category_rule_repo.create(field:, operator:, pattern:, category_id:, origin: "seed", **options)
            added[:rules] += 1
          end
        end

        added
      end

      private

      def ensure_category(added, locale, name:, kind:, parent_id: nil, nature: nil)
        existing = category_repo.find_by(name: Categories.names(name), parent_id:)
        return existing[:id] if existing

        added[:categories] += 1
        category_repo.create(name: Categories.localized(name, locale), kind:, parent_id:, nature:)
      end
    end
  end
end
