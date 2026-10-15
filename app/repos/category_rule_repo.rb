# frozen_string_literal: true

module Tally
  module Repos
    class CategoryRuleRepo < Tally::DB::Repo
      COLUMNS = %i[id priority field operator pattern amount_min_cents amount_max_cents category_id origin hits].freeze

      # The rules that run, in the order they run.
      def active
        category_rules.dataset.where(disabled_at: nil).order(:priority, :id).select(*COLUMNS).all
      end

      # Active rules with their category's name, for the rules page.
      def list
        category_rules.dataset.where(Sequel[:category_rules][:disabled_at] => nil)
          .join(:categories, id: :category_id)
          .select_all(:category_rules).select_append(Sequel[:categories][:name].as(:category_name))
          .order(Sequel[:category_rules][:priority], Sequel[:category_rules][:id]).all
      end

      def find(id) = category_rules.dataset.where(id:).first

      # Any rule with this match, switched off ones included.
      def find_by_match(field:, operator:, pattern:)
        category_rules.dataset.where(field:, operator:, pattern:).first
      end

      def create(**attributes) = category_rules.dataset.insert(**attributes)

      def update(id, **attributes)
        category_rules.dataset.where(id:).update(**attributes, updated_at: Repos.now)
      end

      # Switched off, not deleted: a seed rule you removed is not seeded again.
      def disable(id)
        category_rules.dataset.where(id:, disabled_at: nil).update(disabled_at: Repos.now, updated_at: Repos.now)
      end

      # hits = how many rows each rule categorizes right now.
      def recount_hits
        count = transactions.dataset.unordered
          .where(category_rule_id: Sequel[:category_rules][:id]).select(Sequel.function(:count).*)
        category_rules.dataset.update(hits: count)
      end
    end
  end
end
