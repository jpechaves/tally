# frozen_string_literal: true

require "sqlite3"

module Tally
  # What bin/reset-db uses to keep home bills (issue #113): copies them, their payments and
  # receipt rows from the backup into the new database. Payments link to rows by account
  # name and bank id, and payees by match key, so they find the rows again once the
  # statements are imported; a category is found again by its name and its parent's.
  module HomeBillsCopy
    module_function

    # @return [Integer] how many bills were copied
    def call(from:, to:)
      db = SQLite3::Database.new(to)
      db.execute("ATTACH DATABASE ? AS old", [from])
      return 0 if db.get_first_value("SELECT count(*) FROM old.sqlite_master WHERE name = 'home_bills'").zero?

      db.transaction do
        db.execute(<<~SQL)
          INSERT INTO main.home_bills (id, name, category_id, expected_cents, due_day, payee_key, payee_label, created_at)
          SELECT b.id, b.name, (
            SELECT n.id FROM old.categories o LEFT JOIN old.categories op ON op.id = o.parent_id
            JOIN main.categories n ON n.name = o.name LEFT JOIN main.categories np ON np.id = n.parent_id
            WHERE o.id = b.category_id AND np.name IS op.name
          ), b.expected_cents, b.due_day, b.payee_key, b.payee_label, b.created_at
          FROM old.home_bills b
        SQL
        db.execute("INSERT INTO main.home_bill_payments SELECT * FROM old.home_bill_payments")
        db.execute("INSERT INTO main.home_bill_receipts SELECT * FROM old.home_bill_receipts")
      end
      db.get_first_value("SELECT count(*) FROM main.home_bills")
    ensure
      db.close
    end
  end
end
