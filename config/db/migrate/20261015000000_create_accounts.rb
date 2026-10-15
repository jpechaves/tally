# frozen_string_literal: true

# Conventions for every Tally table (docs/architecture.md, sections 5 and 6):
#
# - `strict: true`, so SQLite rejects a value of the wrong type instead of storing it.
#   STRICT tables only accept the types INTEGER, REAL, TEXT, BLOB and ANY, so columns are
#   declared with `:integer` / `:text`, never Ruby classes like `String` (varchar).
# - Money is whole cents in INTEGER columns named `*_cents`. Never REAL.
# - Timestamps are ISO-8601 UTC text; dates of money events are 'YYYY-MM-DD' text.
# - Nothing is hard-deleted: rows are archived with `archived_at`.
ROM::SQL.migration do
  change do
    create_table :accounts, strict: true do
      primary_key :id
      column :name, :text, null: false, unique: true
      column :kind, :text, null: false
      column :institution, :text
      column :external_ref, :text
      column :currency, :text, null: false, default: "BRL"
      column :opening_balance_cents, :integer, null: false, default: 0
      column :archived_at, :text
      column :created_at, :text, null: false, default: Sequel.lit("(strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))")
      column :updated_at, :text, null: false, default: Sequel.lit("(strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))")

      constraint(:accounts_kind) { Sequel.lit("kind IN ('checking', 'credit_card', 'investment', 'cash')") }
      constraint(:accounts_currency) { Sequel.lit("currency GLOB '[A-Z][A-Z][A-Z]'") }
    end
  end
end
