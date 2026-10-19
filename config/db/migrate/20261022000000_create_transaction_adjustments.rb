# frozen_string_literal: true

# What you know about a row that its statement doesn't say (docs/architecture.md, section
# 6): the purchase was canceled, someone paid it back, or the real amount was different.
# Kept apart from the row, so re-importing the statement (which updates the row) never
# loses it. At most one per row.
#
# - kind: canceled (counts as nothing), reimbursed (counts net of what came back) or
#   amount_changed (counts as amount_cents instead)
# - amount_cents: for reimbursed, what came back (positive); for amount_changed, the real
#   amount, signed like the row; NULL for canceled
# - refund_transaction_id: the row that paid a reimbursement back, when it was imported
#   too (a Pix from a friend, a card refund). It then counts inside this one, not on its own.
ROM::SQL.migration do
  change do
    create_table :transaction_adjustments, strict: true do
      primary_key :id
      foreign_key :transaction_id, :transactions, null: false, unique: true, on_delete: :cascade
      column :kind, :text, null: false
      column :amount_cents, :integer
      foreign_key :refund_transaction_id, :transactions, unique: true, on_delete: :set_null
      column :note, :text
      column :created_at, :text, null: false, default: Sequel.lit("(strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))")
      column :updated_at, :text, null: false, default: Sequel.lit("(strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))")

      constraint(:transaction_adjustments_kind, Sequel.lit("kind IN ('canceled', 'reimbursed', 'amount_changed')"))
      constraint(:transaction_adjustments_amount, Sequel.lit(
        "(kind = 'canceled' AND amount_cents IS NULL) OR " \
        "(kind = 'reimbursed' AND amount_cents > 0) OR (kind = 'amount_changed' AND amount_cents <> 0)"
      ))
      constraint(:transaction_adjustments_refund, Sequel.lit("refund_transaction_id IS NULL OR kind = 'reimbursed'"))
    end
  end
end
