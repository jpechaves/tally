# frozen_string_literal: true

# Your own name for a counterparty, and a note about it (docs/architecture.md, section 4).
# Imports never write them: the bank's name stays in `name`, for matching and rules.
ROM::SQL.migration do
  # Plain SQL, like add_removed_to_budgets: Sequel would rebuild the table and lose STRICT.
  up do
    run "ALTER TABLE counterparties ADD COLUMN display_name text"
    run "ALTER TABLE counterparties ADD COLUMN note text"
  end

  down do
    drop_column :counterparties, :note
    drop_column :counterparties, :display_name
  end
end
