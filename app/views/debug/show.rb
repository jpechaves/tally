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

        # The export button shows only when the download is allowed (Actions::Debug::Export).
        expose(:export_on) { Tally::DatabaseExport.allowed? }

        # The Pi's database backups (Tally::Backups): the last run, its check and the copies.
        # Downloads follow the export rule above.
        expose(:backup_dir) { Tally::Backups.dir }
        expose(:copies, decorate: false) { |backup_dir| backup_dir ? Tally::Backups.copies(backup_dir) : [] }
        expose(:last_run, decorate: false) { |backup_dir| Tally::Backups.last_run(backup_dir) if backup_dir }
        expose(:backup_status) { |backup_dir| Tally::Backups.status(backup_dir) if backup_dir }
      end
    end
  end
end
