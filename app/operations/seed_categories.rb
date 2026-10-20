# frozen_string_literal: true

module Tally
  module Operations
    # Adds the starting categories and generic rules (Tally::Categories) that are not
    # there yet, and moves starting rules a later version rewrote to their new pattern
    # (Categories::REVISED_RULES). Safe to run any time: it never changes or brings back
    # anything you edited, archived or switched off. Runs from config/db/seeds.rb, and on the first
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
          existing = category_repo.ids_by_name_and_parent

          Categories::EXPENSES.each do |parent, children|
            parent_id = ensure_category(added, existing, locale, name: parent, kind: "expense")
            children.each do |name, nature|
              ensure_category(added, existing, locale, name:, kind: "expense", parent_id:, nature:)
            end
          end

          Categories::INCOME.each do |parent, children|
            parent_id = ensure_category(added, existing, locale, name: parent, kind: "income")
            children.each { ensure_category(added, existing, locale, name: _1, kind: "income", parent_id:) }
          end

          rules = category_rule_repo.by_match
          Categories::REVISED_RULES.each do |(field, operator, old), pattern|
            rule = rules[[field, operator, old]]
            next unless rule && rule[:origin] == "seed" && !rules[[field, operator, pattern]]

            category_rule_repo.update(rule[:id], pattern:)
            rules[[field, operator, pattern]] = rule
          end

          ids = category_repo.ids_by_name(Categories::RULES.flat_map { Categories.names(_1[3]) })
          Categories::RULES.each do |field, operator, pattern, category, options = {}|
            next if rules[[field, operator, pattern]]

            category_id = Categories.names(category).filter_map { ids[_1] }.first or raise ArgumentError, "no category #{category}"
            category_rule_repo.create(field:, operator:, pattern:, category_id:, origin: "seed", **options)
            added[:rules] += 1
          end
        end

        added
      end

      private

      def ensure_category(added, existing, locale, name:, kind:, parent_id: nil, nature: nil)
        id = Categories.names(name).filter_map { existing[[_1, parent_id]] }.first
        return id if id

        added[:categories] += 1
        category_repo.create(name: Categories.localized(name, locale), kind:, parent_id:, nature:)
      end
    end
  end
end
