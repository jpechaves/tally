# frozen_string_literal: true

# Removing a category's budget from a month on (docs/architecture.md, section 6). A budget
# row applies from its month until the category's next row, so a removed row (removed = 1)
# ends the one before it without changing the months that one already covered.
ROM::SQL.migration do
  # Plain SQL: Sequel would rebuild the table for the CHECK, and lose STRICT.
  up do
    run "ALTER TABLE budgets ADD COLUMN removed integer NOT NULL DEFAULT 0 CHECK (removed IN (0, 1))"
  end

  down do
    drop_column :budgets, :removed
  end
end
