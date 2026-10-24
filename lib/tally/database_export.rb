# frozen_string_literal: true

require "sequel"

module Tally
  # A copy of the live database to download from the Debug info page (issue #136,
  # docs/architecture.md, section 10.3). SQLite's VACUUM INTO writes a consistent snapshot
  # even while the app writes in WAL mode, and the copy passes PRAGMA integrity_check
  # before anyone gets it. Only the database: receipts and imported files stay in storage/.
  module DatabaseExport
    class Damaged < StandardError; end

    module_function

    # Writes the copy to a new file in +dir+, named after +now+, and returns its path.
    def write(db, dir, now: Time.now)
      path = File.join(dir, now.strftime("tally-%Y%m%d-%H%M%S.sqlite"))
      db.run("VACUUM INTO #{db.literal(path)}")
      check(path)
      path
    end

    def check(path)
      Sequel.sqlite(path) do |copy|
        result = copy.fetch("PRAGMA integrity_check").single_value
        raise Damaged, "integrity check of #{File.basename(path)}: #{result}" unless result == "ok"
      end
    end
  end
end
