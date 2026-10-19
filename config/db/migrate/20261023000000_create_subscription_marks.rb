# frozen_string_literal: true

# What you said about a payee on the subscriptions page (issue #74, docs/architecture.md,
# section 8.7): "dismissed" (not a subscription) or "marked" (one, found or not). Keyed by
# the payee (Tally::Insights.payee_key), not by rows, so re-importing keeps it.
ROM::SQL.migration do
  change do
    create_table :subscription_marks, strict: true do
      primary_key :id
      column :key, :text, null: false, unique: true
      column :kind, :text, null: false
      column :title, :text, null: false # the payee's name then, so the list reads well
      column :created_at, :text, null: false, default: Sequel.lit("(strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))")

      constraint(:subscription_marks_kind, Sequel.lit("kind IN ('dismissed', 'marked')"))
    end
  end
end
