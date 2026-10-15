# frozen_string_literal: true

# Statement import (docs/architecture.md section 6, docs/statement-import.md section 4).
# Same conventions as the accounts table: STRICT, money in *_cents INTEGER, dates as
# 'YYYY-MM-DD' text, timestamps as ISO-8601 UTC text.
#
# Categories and rules arrive in milestone 3, which adds their columns to transactions.
ROM::SQL.migration do
  change do
    now = Sequel.lit("(strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))")

    # An account with no statement of its own (Itaú conta, Nubank RDB): every transfer
    # into or out of it is mirrored there, so its balance is still a plain SUM.
    alter_table :accounts do
      add_column :mirror_transfers, :integer, null: false, default: 0
    end

    create_table :counterparties, strict: true do
      primary_key :id
      column :name, :text, null: false
      column :document, :text            # full CNPJ, or masked CPF "•••.123.456-••"
      column :document_kind, :text       # cnpj | cpf_masked
      # Identity: document + name, upper-cased ("" when there is no document). A column,
      # because SQLite's UNIQUE treats every NULL document as different.
      column :match_key, :text, null: false, unique: true
      column :bank_name, :text
      column :bank_code, :text
      column :branch, :text
      column :account_number, :text
      # You, at another bank: Pix to or from it is a transfer, never spending.
      column :is_self, :integer, null: false, default: 0
      column :created_at, :text, null: false, default: now
      column :updated_at, :text, null: false, default: now

      constraint(:counterparties_document_kind) { Sequel.lit("document_kind IN ('cnpj', 'cpf_masked')") }
      constraint(:counterparties_is_self) { Sequel.lit("is_self IN (0, 1)") }
    end

    create_table :imports, strict: true do
      primary_key :id
      foreign_key :account_id, :accounts, type: :integer
      column :source, :text, null: false
      column :file_name, :text, null: false
      column :file_sha256, :text, null: false
      column :file_size, :integer, null: false
      column :period_start, :text
      column :period_end, :text
      column :status, :text, null: false
      column :rows_inserted, :integer, null: false, default: 0
      column :rows_updated, :integer, null: false, default: 0
      column :rows_unchanged, :integer, null: false, default: 0
      column :rows_missing, :integer, null: false, default: 0
      column :warnings, :text, null: false, default: "[]"   # JSON array of strings
      column :error, :text
      column :created_at, :text, null: false, default: now
      column :updated_at, :text, null: false, default: now

      constraint(:imports_status) { Sequel.lit("status IN ('applied', 'duplicate_file', 'rejected')") }
      index :file_sha256
    end

    # One per bill. Amounts are as printed: the total owed is positive.
    create_table :card_statements, strict: true do
      primary_key :id
      foreign_key :account_id, :accounts, type: :integer, null: false
      column :closing_on, :text       # unknown for Nubank exports
      column :due_on, :text, null: false
      column :total_cents, :integer, null: false
      column :previous_total_cents, :integer
      column :payments_cents, :integer, null: false, default: 0
      column :purchases_cents, :integer, null: false, default: 0
      column :fees_cents, :integer, null: false, default: 0
      column :next_statement_cents, :integer      # installments already committed
      column :later_statements_cents, :integer
      column :credit_limit_cents, :integer
      column :available_limit_cents, :integer
      foreign_key :import_id, :imports, type: :integer, null: false
      column :created_at, :text, null: false, default: now
      column :updated_at, :text, null: false, default: now

      unique %i[account_id due_on]
    end

    # Exactly two legs that sum to zero, or one leg until the other account is imported.
    create_table :transfers, strict: true do
      primary_key :id
      column :occurred_on, :text, null: false
      column :memo, :text
      column :created_at, :text, null: false, default: now
      column :updated_at, :text, null: false, default: now
    end

    create_table :transactions, strict: true do
      primary_key :id
      foreign_key :account_id, :accounts, type: :integer, null: false
      column :occurred_on, :text, null: false     # the date that counts for reports
      column :purchased_on, :text                 # original purchase date (installments)
      column :amount_cents, :integer, null: false
      column :kind, :text, null: false
      foreign_key :transfer_id, :transfers, type: :integer
      # For transfers: the other account (known even before its leg is imported).
      foreign_key :counter_account_id, :accounts, type: :integer
      foreign_key :counterparty_id, :counterparties, type: :integer
      column :description, :text, null: false     # cleaned
      column :raw_description, :text, null: false # exactly as in the statement
      column :bank_category, :text                # Itaú's "vestuário", "supermercado", ...
      column :location, :text                     # Itaú's city
      column :installment_number, :integer
      column :installment_total, :integer
      column :purchase_key, :text                 # links installments across bills
      foreign_key :card_statement_id, :card_statements, type: :integer
      column :memo, :text                         # yours; imports never touch it
      column :external_id, :text, null: false     # upsert key within the account
      foreign_key :first_import_id, :imports, type: :integer
      foreign_key :last_import_id, :imports, type: :integer
      foreign_key :missing_since_import_id, :imports, type: :integer
      column :raw_json, :text                     # the source row, for audit
      column :created_at, :text, null: false, default: now
      column :updated_at, :text, null: false, default: now

      constraint(:transactions_amount) { Sequel.lit("amount_cents <> 0") }
      constraint(:transactions_kind) do
        Sequel.lit("kind IN ('purchase', 'refund', 'fee', 'income', 'transfer', 'bill_payment')")
      end
      constraint(:transactions_installment) do
        Sequel.lit("(installment_number IS NULL) = (installment_total IS NULL)")
      end

      unique %i[account_id external_id]
      index %i[account_id occurred_on]
      index :counterparty_id
      index :transfer_id
      index :card_statement_id
    end
  end
end
