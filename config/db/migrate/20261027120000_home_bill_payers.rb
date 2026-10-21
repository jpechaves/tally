# frozen_string_literal: true

# Who paid a home bill is a person of the household (issue #125), kept by name like the
# linked row's account, so bin/reset-db keeps it. What was typed by hand becomes the person
# it names, ignoring case and spaces; anything else stays as it was typed. A month linked
# to a row was paid by that row's account's owner.
ROM::SQL.migration do
  up do
    run <<~SQL
      UPDATE home_bill_payments SET paid_by = (SELECT name FROM people WHERE lower(name) = lower(trim(paid_by)))
      WHERE EXISTS (SELECT 1 FROM people WHERE lower(name) = lower(trim(paid_by)))
    SQL
    run <<~SQL
      UPDATE home_bill_payments SET paid_by = (
        SELECT people.name FROM accounts JOIN people ON people.id = accounts.person_id WHERE accounts.name = account_name
      ) WHERE paid_by IS NULL AND account_name IS NOT NULL
    SQL
  end

  # The names stay: they were what "who paid" showed before too.
  down {}
end
