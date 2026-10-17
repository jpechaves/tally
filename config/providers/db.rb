# frozen_string_literal: true

# SQLite settings for precision and durability (docs/architecture.md, section 9).
# They are applied to every new connection.
Hanami.app.configure_provider :db do
  config.gateway :default do |gw|
    gw.connection_options(
      # Enforce REFERENCES constraints (SQLite leaves them off by default).
      foreign_keys: true,
      # Wait up to 5s for a lock instead of failing on concurrent writes.
      timeout: 5_000,
      # Writes are rare; pay for durability on an SD card that may lose power.
      synchronous: :full,
      # Readers don't block the writer, and a crash mid-write is safer.
      connect_sqls: ["PRAGMA journal_mode = WAL"],
      # Name searches that ignore accents and case (Tally::Search), payees grouped
      # like the review list and the report (Tally::Review.key), and card merchants
      # matched to companies (Tally::Merchants.key).
      after_connect: lambda { |connection|
        Tally::Search.register(connection)
        Tally::Review.register(connection)
        Tally::Merchants.register(connection)
      }
    )
  end
end
