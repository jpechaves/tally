# frozen_string_literal: true

require "tmpdir"

RSpec.describe "Backups", type: :request do
  it "explains where backups come from when this machine has none" do
    get "/backups"

    expect(last_response.status).to eq(200)
    expect(last_response.body).to include("<h1>Backups</h1>", %(<a href="/backups" aria-current="page">), "BACKUP_DIR")

    get "/"
    expect(last_response.body).not_to include("No backup in the last", "The last backup failed")
  end

  context "with a backups folder" do
    around { |example| Dir.mktmpdir { |dir| @dir = dir and example.run } }

    let(:now) { Time.utc(2026, 10, 25, 12, 0, 0) }

    before do
      allow(Hanami.app["settings"]).to receive(:backup_dir).and_return(@dir)
      allow(Time).to receive(:now).and_return(now)
      File.write(File.join(@dir, "nightly-20261025-033000.sqlite"), "SQLite format 3\0")
      File.utime(now - 5 * 3600, now - 5 * 3600, File.join(@dir, "nightly-20261025-033000.sqlite"))
      File.write(File.join(@dir, "log.jsonl"), %({"time":"2026-10-25T06:30:00Z","kind":"nightly","file":"nightly-20261025-033000.sqlite","bytes":16,"check":"ok"}\n))
    end

    it "shows the last run and the copies, without download links while the login is off" do
      get "/backups"

      expect(last_response.body).to include("Oct 25, 2026 03:30", "nightly-20261025-033000.sqlite", @dir, "bin/pull-backup")
      expect(last_response.body).to include("Integrity check passed", "Downloads need the login on")
      expect(last_response.body).not_to include(%(href="/backups/nightly))

      get "/backups/nightly-20261025-033000.sqlite"
      expect(last_response.status).to eq(403)

      get "/"
      expect(last_response.body).not_to include("No backup in the last", "The last backup failed")
    end

    it "downloads a copy when allowed, and only files from the folder" do
      allow(Hanami.app["settings"]).to receive(:allow_export_without_login).and_return(true)

      get "/backups"
      expect(last_response.body).to include(%(href="/backups/nightly-20261025-033000.sqlite"))

      get "/backups/nightly-20261025-033000.sqlite"
      expect(last_response.status).to eq(200)
      expect(last_response.headers["Content-Disposition"]).to eq(%(attachment; filename="nightly-20261025-033000.sqlite"))
      expect(last_response.body).to start_with("SQLite format 3\0")

      get "/backups/nightly-20261024-033000.sqlite"
      expect(last_response.status).to eq(404)
      get "/backups/log.jsonl"
      expect(last_response.status).to eq(404)
    end

    it "warns on the page and at home when the newest copy is old" do
      allow(Time).to receive(:now).and_return(now + 2 * 86_400)

      get "/backups"
      expect(last_response.body).to include(%(<p class="warning">No backup in the last 36 hours.))

      get "/"
      expect(last_response.body).to include(%(<p class="warning"><a href="/backups">No backup in the last 36 hours.))
    end

    it "warns when the last check failed" do
      File.write(File.join(@dir, "log.jsonl"), %({"time":"2026-10-25T11:00:00Z","kind":"pre-deploy","file":"pre-deploy-20261025-080000.sqlite","bytes":0,"check":"row 3 missing from index"}\n), mode: "a")

      get "/backups"
      expect(last_response.body).to include("The last backup failed: row 3 missing from index")

      get "/"
      expect(last_response.body).to include("The last backup failed: row 3 missing from index")
    end
  end
end
