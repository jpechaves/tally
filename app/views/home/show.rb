# frozen_string_literal: true

module Tally
  module Views
    module Home
      class Show < Tally::View
        include Deps["db.gateway"]

        # The SQLite settings actually in effect, so a fresh install (e.g. on the Pi) can be
        # checked at a glance.
        expose :database do
          db = gateway.connection
          pragma = ->(name) { db.fetch("PRAGMA #{name}").single_value }

          {
            "SQLite version" => db.fetch("SELECT sqlite_version()").single_value,
            "Journal mode" => pragma.("journal_mode"),
            "Foreign keys" => pragma.("foreign_keys") == 1 ? "on" : "off",
            "Synchronous" => {0 => "off", 1 => "normal", 2 => "full", 3 => "extra"}.fetch(pragma.("synchronous")),
            "Busy timeout" => "#{pragma.("busy_timeout")} ms"
          }
        end
      end
    end
  end
end
