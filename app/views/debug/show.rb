# frozen_string_literal: true

module Tally
  module Views
    module Debug
      # How this install is set up, for checking a fresh one (e.g. on the Pi) at a glance.
      class Show < Tally::View
        include Deps["db.gateway"]

        # The SQLite settings actually in effect.
        expose :database do
          db = gateway.connection
          pragma = ->(name) { db.fetch("PRAGMA #{name}").single_value }

          {
            sqlite_version: db.fetch("SELECT sqlite_version()").single_value,
            journal_mode: pragma.call("journal_mode"),
            foreign_keys: (pragma.call("foreign_keys") == 1) ? "on" : "off",
            synchronous: {0 => "off", 1 => "normal", 2 => "full", 3 => "extra"}.fetch(pragma.call("synchronous")),
            busy_timeout: "#{pragma.call("busy_timeout")} ms"
          }
        end

        # The export button shows only behind the login (Actions::Debug::Export).
        expose(:export_on) { Tally::BasicAuth.on? }
      end
    end
  end
end
