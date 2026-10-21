# frozen_string_literal: true

# One adjustment for every installment of a card purchase (issue #69): canceled, a total
# that came back, or the purchase's real total. Each installment gets its own
# transaction_adjustments row pointing here, so taking the purchase's adjustment out takes
# them all out, and installments imported later get theirs as they arrive.
#
# - transaction_id: the installment it was made from (the purchase is found from it)
# - kind: canceled, reimbursed or amount_changed, as in transaction_adjustments
# - amount_cents: for the whole purchase, positive: what came back or its real total;
#   NULL for canceled
# - through_transaction_id: the newest installment already adjusted; later ones are new
ROM::SQL.migration do
  change do
    create_table :purchase_adjustments, strict: true do
      primary_key :id
      foreign_key :transaction_id, :transactions, null: false, unique: true, on_delete: :cascade
      column :kind, :text, null: false
      column :amount_cents, :integer
      column :note, :text
      column :through_transaction_id, :integer, null: false
      column :created_at, :text, null: false, default: Sequel.lit("(strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))")

      constraint(:purchase_adjustments_kind, Sequel.lit("kind IN ('canceled', 'reimbursed', 'amount_changed')"))
      constraint(:purchase_adjustments_amount, Sequel.lit("(kind = 'canceled') = (amount_cents IS NULL) AND (amount_cents IS NULL OR amount_cents > 0)"))
    end

    alter_table :transaction_adjustments do
      add_foreign_key :purchase_adjustment_id, :purchase_adjustments, on_delete: :cascade
    end
  end
end
