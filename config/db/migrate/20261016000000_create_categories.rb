# frozen_string_literal: true

# Categorization (docs/architecture.md section 6, docs/statement-import.md section 6).
ROM::SQL.migration do
  change do
    now = Sequel.lit("(strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))")

    # Two levels: a parent ("Moradia") and its categories ("Energia"). Rows can sit on either.
    create_table :categories, strict: true do
      primary_key :id
      column :name, :text, null: false
      foreign_key :parent_id, :categories, type: :integer
      column :kind, :text, null: false
      # Expenses only. Drives the savings planner: how far it may cut the category.
      column :nature, :text
      column :max_cut_pct, :integer
      column :archived_at, :text
      column :created_at, :text, null: false, default: now
      column :updated_at, :text, null: false, default: now

      constraint(:categories_kind) { Sequel.lit("kind IN ('expense', 'income')") }
      constraint(:categories_nature) { Sequel.lit("nature IN ('fixed', 'essential', 'discretionary')") }
      constraint(:categories_max_cut_pct) { Sequel.lit("max_cut_pct BETWEEN 0 AND 100") }
    end
    # UNIQUE(parent_id, name) alone would let top-level categories (NULL parent) repeat a
    # name. Two partial indexes, since an expression index breaks schema inference.
    add_index :categories, %i[parent_id name], unique: true, where: Sequel.~(parent_id: nil), name: :categories_parent_name
    add_index :categories, :name, unique: true, where: {parent_id: nil}, name: :categories_top_name

    create_table :category_rules, strict: true do
      primary_key :id
      column :priority, :integer, null: false, default: 100 # lower runs first
      column :field, :text, null: false
      column :operator, :text, null: false
      column :pattern, :text, null: false
      column :amount_min_cents, :integer
      column :amount_max_cents, :integer
      foreign_key :category_id, :categories, type: :integer, null: false
      column :origin, :text, null: false
      column :hits, :integer, null: false, default: 0
      # Rules are switched off, not deleted, so a seed rule you removed stays removed.
      column :disabled_at, :text
      column :created_at, :text, null: false, default: now
      column :updated_at, :text, null: false, default: now

      constraint(:category_rules_field) do
        Sequel.lit("field IN ('counterparty_document', 'counterparty_name', 'description', 'bank_category', 'kind')")
      end
      constraint(:category_rules_operator) { Sequel.lit("operator IN ('equals', 'contains', 'starts_with', 'regex')") }
      constraint(:category_rules_origin) { Sequel.lit("origin IN ('seed', 'learned', 'manual')") }
      index %i[priority id]
    end

    alter_table :counterparties do
      add_foreign_key :default_category_id, :categories, type: :integer
    end

    alter_table :transactions do
      add_foreign_key :category_id, :categories, type: :integer
      # none | bank (a suggestion from the bank's own category) | rule | manual.
      # Manual is yours: imports and rules never change it.
      add_column :category_source, :text, null: false, default: "none"
      add_foreign_key :category_rule_id, :category_rules, type: :integer
      add_index %i[category_id occurred_on]
    end
  end
end
