# frozen_string_literal: true

require "sqlite3"

module Tally
  # What bin/reset-db uses to keep the travel list (issue #165): your words replace the
  # starting ones the migration put in the new database.
  module TravelWordsCopy
    module_function

    # @return [Integer, nil] how many words were copied; nil from a database from before the list
    def call(from:, to:)
      db = SQLite3::Database.new(to)
      db.execute("ATTACH DATABASE ? AS old", [from])
      return if db.get_first_value("SELECT count(*) FROM old.sqlite_master WHERE name = 'travel_words'").zero?

      db.transaction do
        db.execute("DELETE FROM main.travel_words")
        db.execute("INSERT INTO main.travel_words SELECT * FROM old.travel_words")
      end
      db.get_first_value("SELECT count(*) FROM main.travel_words")
    ensure
      db.close
    end
  end
end
