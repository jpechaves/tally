# frozen_string_literal: true

require "json"
require "time"

module Tally
  # The Pi's database backups, for the Backups section of the Debug info page and the home
  # warning (issue #137, docs/architecture.md, section 10.3). deploy/pi/backup.sh writes the
  # copies into one folder (BACKUP_DIR) and one line per run to its log.jsonl; this only reads them.
  module Backups
    STALE_AFTER = 36 * 3600
    LOG = "log.jsonl"
    FILE = /\A(?<kind>[a-z-]+)-\d{8}-\d{6}\.sqlite\z/

    Copy = Data.define(:file, :kind, :time, :bytes)
    Run = Data.define(:time, :kind, :file, :bytes, :check) do
      def ok? = check == "ok"
    end

    module_function

    # The backups folder, or nil where there is none (development).
    def dir(settings = Hanami.app["settings"])
      settings.backup_dir.to_s.strip.then { _1 unless _1.empty? }
    end

    def copies(dir)
      Dir.children(dir).filter_map do |file|
        kind = FILE.match(file)&.[](:kind) or next
        stat = File.stat(File.join(dir, file))
        Copy.new(file:, kind:, time: stat.mtime, bytes: stat.size)
      end.sort_by(&:time).reverse
    rescue Errno::ENOENT
      []
    end

    def last_run(dir)
      path = File.join(dir, LOG)
      return unless File.exist?(path)

      line = JSON.parse(File.readlines(path, chomp: true).last, symbolize_names: true)
      Run.new(**line.slice(*Run.members), time: Time.iso8601(line[:time]))
    end

    # :failed when the last run's check didn't pass, :stale when the newest copy is older
    # than STALE_AFTER (or there is none), else :ok.
    def status(dir, now: Time.now)
      return :failed if last_run(dir)&.ok? == false

      newest = copies(dir).first
      (newest && newest.time > now - STALE_AFTER) ? :ok : :stale
    end
  end
end
