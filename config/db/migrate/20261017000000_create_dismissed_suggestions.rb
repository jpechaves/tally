# frozen_string_literal: true

# Cut suggestions you dismissed (docs/architecture.md, section 8.3): one row per key, so a
# dismissed payee or category stays quiet.
ROM::SQL.migration do
  change do
    create_table :dismissed_suggestions, strict: true do
      primary_key :id
      column :key, :text, null: false, unique: true
      column :title, :text, null: false # what it said, so the list of dismissed ones reads well
      column :created_at, :text, null: false, default: Sequel.lit("(strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))")
    end
  end
end
