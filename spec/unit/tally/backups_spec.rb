# frozen_string_literal: true

require "tmpdir"

RSpec.describe Tally::Backups do
  around { |example| Dir.mktmpdir { |dir| @dir = dir and example.run } }

  let(:now) { Time.utc(2026, 10, 25, 12, 0, 0) }

  def copy(file, at:, bytes: 3)
    path = File.join(@dir, file)
    File.write(path, "x" * bytes)
    File.utime(at, at, path)
  end

  def log(*lines)
    File.write(File.join(@dir, "log.jsonl"), lines.map { "#{JSON.generate(_1)}\n" }.join)
  end

  describe ".dir" do
    it "is the BACKUP_DIR setting, or nil when it is blank" do
      expect(described_class.dir(double(backup_dir: " /pi/backups "))).to eq("/pi/backups")
      expect(described_class.dir(double(backup_dir: " "))).to be_nil
      expect(described_class.dir(double(backup_dir: nil))).to be_nil
    end
  end

  describe ".copies" do
    it "lists the backup files, newest first, with their kind and size" do
      copy("nightly-20261024-033000.sqlite", at: now - 30 * 3600, bytes: 5)
      copy("pre-deploy-20261025-101500.sqlite", at: now - 2 * 3600)
      copy("notes.txt", at: now)

      copies = described_class.copies(@dir)
      expect(copies.map(&:file)).to eq(%w[pre-deploy-20261025-101500.sqlite nightly-20261024-033000.sqlite])
      expect(copies.map(&:kind)).to eq(%w[pre-deploy nightly])
      expect(copies.last).to have_attributes(time: now - 30 * 3600, bytes: 5)
    end

    it "is empty when the folder isn't there" do
      expect(described_class.copies(File.join(@dir, "missing"))).to eq([])
    end
  end

  describe ".last_run" do
    it "reads the newest line of the log" do
      log({time: "2026-10-24T06:30:00Z", kind: "nightly", file: "a.sqlite", bytes: 5, check: "ok"},
        {time: "2026-10-25T06:30:00Z", kind: "nightly", file: "b.sqlite", bytes: 0, check: "row 3 missing from index"})

      run = described_class.last_run(@dir)
      expect(run).to have_attributes(time: Time.utc(2026, 10, 25, 6, 30), kind: "nightly", check: "row 3 missing from index")
      expect(run).not_to be_ok
    end

    it "is nil without a log" do
      expect(described_class.last_run(@dir)).to be_nil
    end
  end

  describe ".status" do
    it "is ok while the newest copy is recent and the last check passed" do
      copy("nightly-20261025-033000.sqlite", at: now - 9 * 3600)
      log({time: "2026-10-25T06:30:00Z", kind: "nightly", file: "x", bytes: 3, check: "ok"})

      expect(described_class.status(@dir, now:)).to eq(:ok)
    end

    it "is stale when the newest copy is older than 36 hours, or there is none" do
      expect(described_class.status(@dir, now:)).to eq(:stale)

      copy("nightly-20261023-033000.sqlite", at: now - 37 * 3600)
      expect(described_class.status(@dir, now:)).to eq(:stale)
    end

    it "is failed when the last check didn't pass" do
      copy("nightly-20261025-033000.sqlite", at: now - 3600)
      log({time: "2026-10-25T11:00:00Z", kind: "nightly", file: "x", bytes: 0, check: "failed"})

      expect(described_class.status(@dir, now:)).to eq(:failed)
    end
  end
end
