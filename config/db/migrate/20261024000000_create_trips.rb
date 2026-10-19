# frozen_string_literal: true

# Trips (issue #75, docs/architecture.md, section 8.8): a name and a date range, the
# accounts to look in (none listed means all), and your choices of rows to add or take out.
# Choices are kept apart from the rows, so re-importing a statement keeps them.
ROM::SQL.migration do
  change do
    create_table :trips, strict: true do
      primary_key :id
      column :name, :text, null: false
      column :starts_on, :text, null: false
      column :ends_on, :text, null: false
      column :created_at, :text, null: false, default: Sequel.lit("(strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))")

      constraint(:trips_dates, Sequel.lit("starts_on <= ends_on"))
    end

    create_table :trip_accounts, strict: true do
      foreign_key :trip_id, :trips, null: false, on_delete: :cascade
      foreign_key :account_id, :accounts, null: false, on_delete: :cascade
      primary_key %i[trip_id account_id]
    end

    # included: 1 adds the row (or its whole card purchase), 0 takes it out.
    create_table :trip_rows, strict: true do
      foreign_key :trip_id, :trips, null: false, on_delete: :cascade
      foreign_key :transaction_id, :transactions, null: false, on_delete: :cascade
      column :included, :integer, null: false
      primary_key %i[trip_id transaction_id]

      constraint(:trip_rows_included, Sequel.lit("included IN (0, 1)"))
    end
  end
end
