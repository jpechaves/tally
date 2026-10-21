# frozen_string_literal: true

# Home bills (issue #113, docs/architecture.md, section 8.9): rent, energy, water, internet,
# each with a due day; who paid each month, and photos of the receipts.
#
# Nothing here points at a row id that bin/reset-db throws away: a payment links to its
# transaction by account name and the bank's external_id (the re-import upsert key), and a
# payee is kept by its key (Tally::Insights.payee_key). bin/reset-db copies these tables over.
ROM::SQL.migration do
  change do
    create_table :home_bills, strict: true do
      primary_key :id
      column :name, :text, null: false
      foreign_key :category_id, :categories, on_delete: :set_null
      column :expected_cents, :integer
      column :due_day, :integer, null: false
      column :payee_key, :text
      column :payee_label, :text
      column :created_at, :text, null: false, default: Sequel.lit("(strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))")

      constraint(:home_bills_due_day, Sequel.lit("due_day BETWEEN 1 AND 31"))
    end

    # One payment per bill and month: a linked transaction, or one paid by hand.
    create_table :home_bill_payments, strict: true do
      foreign_key :home_bill_id, :home_bills, null: false, on_delete: :cascade
      column :month, :text, null: false
      column :paid_on, :text, null: false
      column :amount_cents, :integer, null: false
      column :paid_by, :text
      column :account_name, :text
      column :external_id, :text
      column :created_at, :text, null: false, default: Sequel.lit("(strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))")
      primary_key %i[home_bill_id month]

      constraint(:home_bill_payments_link, Sequel.lit("(account_name IS NULL) = (external_id IS NULL)"))
    end

    # Receipt files live on disk (Settings#receipt_storage_dir), named by their SHA-256.
    create_table :home_bill_receipts, strict: true do
      primary_key :id
      foreign_key :home_bill_id, :home_bills, null: false, on_delete: :cascade
      column :month, :text, null: false
      column :sha256, :text, null: false
      column :mime, :text, null: false
      column :byte_size, :integer, null: false
      column :filename, :text, null: false
      column :uploaded_at, :text, null: false, default: Sequel.lit("(strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))")

      index %i[home_bill_id month]
    end
  end
end
