# frozen_string_literal: true

# The savings planner and budgets (docs/architecture.md, sections 6 and 8.4).
ROM::SQL.migration do
  change do
    now = Sequel.lit("(strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))")

    create_table :savings_plans, strict: true do
      primary_key :id
      column :target_cents, :integer, null: false
      column :baseline_from, :text, null: false # YYYY-MM
      column :baseline_to, :text, null: false
      column :baseline_income_cents, :integer, null: false
      column :baseline_spending_cents, :integer, null: false
      column :starts_month, :text, null: false
      column :status, :text, null: false, default: "draft"
      column :shortfall_cents, :integer, null: false, default: 0
      column :created_at, :text, null: false, default: now
      column :updated_at, :text, null: false, default: now

      constraint(:savings_plans_target) { Sequel.lit("target_cents > 0") }
      constraint(:savings_plans_status) { Sequel.lit("status IN ('draft', 'active', 'replaced')") }
    end

    create_table :savings_plan_lines, strict: true do
      primary_key :id
      foreign_key :savings_plan_id, :savings_plans, type: :integer, null: false, on_delete: :cascade
      foreign_key :category_id, :categories, type: :integer, null: false
      column :baseline_cents, :integer, null: false # average monthly spend
      column :max_cut_cents, :integer, null: false # what the nature allows
      column :proposed_cents, :integer, null: false # the new monthly limit

      constraint(:savings_plan_lines_proposed) { Sequel.lit("proposed_cents >= 0") }
      index %i[savings_plan_id category_id], unique: true
    end

    create_table :budgets, strict: true do
      primary_key :id
      foreign_key :category_id, :categories, type: :integer, null: false
      column :month, :text, null: false # YYYY-MM, the first month it applies to
      column :amount_cents, :integer, null: false
      foreign_key :savings_plan_id, :savings_plans, type: :integer
      column :created_at, :text, null: false, default: now
      column :updated_at, :text, null: false, default: now

      constraint(:budgets_amount) { Sequel.lit("amount_cents >= 0") }
      index %i[category_id month], unique: true
    end
  end
end
