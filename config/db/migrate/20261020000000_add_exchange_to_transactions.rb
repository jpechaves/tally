# frozen_string_literal: true

# What a row in a foreign-currency account (Conta Global, in USD) says about the exchange
# behind it (docs/statement-import.md, section 2c). The row's own amount_cents stays in its
# account's currency; these only describe the other side.
#
# - exchange_currency: the other currency (GBP for a card purchase in London, BRL for a
#   top-up from Nubank conta)
# - exchange_amount_cents: the amount in that currency, signed like the row; NULL when the
#   statement doesn't print it (top-ups)
# - exchange_rate: units of exchange_currency per one unit of the account's currency, as
#   decimal text ("0.7825"), so pairing a top-up with its BRL leg can check the amount
# - fee_cents: the bank's fee, in the account's currency, already inside amount_cents
ROM::SQL.migration do
  # Plain SQL: Sequel would rebuild the table for the CHECK, and lose STRICT.
  up do
    run "ALTER TABLE transactions ADD COLUMN exchange_currency text " \
      "CHECK (exchange_currency IS NULL OR exchange_currency GLOB '[A-Z][A-Z][A-Z]')"
    run "ALTER TABLE transactions ADD COLUMN exchange_amount_cents integer"
    run "ALTER TABLE transactions ADD COLUMN exchange_rate text"
    run "ALTER TABLE transactions ADD COLUMN fee_cents integer CHECK (fee_cents IS NULL OR fee_cents > 0)"
  end

  down do
    drop_column :transactions, :fee_cents
    drop_column :transactions, :exchange_rate
    drop_column :transactions, :exchange_amount_cents
    drop_column :transactions, :exchange_currency
  end
end
