# frozen_string_literal: true

# What the bank showed as an account's balance on a day, typed in on the accounts page.
# The newest check anchors the balance Tally shows (it plus the rows after it), and each
# check after the first tells whether the rows between them add up: a difference means a
# row is missing, or one is there twice.
#
# - checked_on: the day the bank showed the balance, at the end of that day
# - balance_cents: the balance, negative for a card's open bill
ROM::SQL.migration do
  change do
    create_table :balance_checks, strict: true do
      primary_key :id
      foreign_key :account_id, :accounts, null: false, on_delete: :cascade
      column :checked_on, :text, null: false
      column :balance_cents, :integer, null: false
      column :created_at, :text, null: false, default: Sequel.lit("(strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))")

      unique %i[account_id checked_on]
    end
  end
end
