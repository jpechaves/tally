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
            sqlite_version: db.fetch("SELECT sqlite_version()").single_value,
            journal_mode: pragma.("journal_mode"),
            foreign_keys: pragma.("foreign_keys") == 1 ? "on" : "off",
            synchronous: {0 => "off", 1 => "normal", 2 => "full", 3 => "extra"}.fetch(pragma.("synchronous")),
            busy_timeout: "#{pragma.("busy_timeout")} ms"
          }
        end
      end
    end
  end
end
