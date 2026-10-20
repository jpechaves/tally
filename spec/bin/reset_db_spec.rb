# frozen_string_literal: true

require "open3"
require "sqlite3"
require "tmpdir"

RSpec.describe "bin/reset-db" do
  around { |example| Dir.mktmpdir { |dir| @dir = dir and example.run } }

  let(:path) { File.join(@dir, "tally.sqlite") }

  def reset(*args, env: "development", input: "")
    Open3.capture2e({"HANAMI_ENV" => env, "DATABASE_URL" => "sqlite://#{path}"},
      Hanami.app.root.join("bin", "reset-db").to_s, *args, stdin_data: input)
  end

  def query(sql, file = path)
    db = SQLite3::Database.new(file)
    db.get_first_value(sql)
  ensure
    db&.close
  end

  # One example: each reset boots the app three times.
  it "asks first, backs the database up, then recreates it with the schema and the starting categories, keeping home bills" do
    output, status = reset("--force")
    expect(status).to be_success, output
    query("INSERT INTO accounts (name, institution, kind) VALUES ('Conta exemplo', 'nubank', 'checking')")

    output, status = reset(input: "y\n")
    expect(status).not_to be_success
    expect(output).to include("This deletes everything in #{path}", "Nothing was changed")
    expect(query("SELECT count(*) FROM accounts")).to eq(1)

    query("INSERT INTO home_bills (name, due_day) VALUES ('Energia', 10)")

    output, status = reset(input: "yes\n")
    expect(status).to be_success, output
    backups = Dir[File.join(@dir, "tally-backup-*.sqlite")]
    expect(backups.size).to eq(1)
    expect(output).to include("Backed up to #{backups.first}")
    expect(query("SELECT count(*) FROM accounts", backups.first)).to eq(1)
    expect(query("SELECT count(*) FROM accounts")).to eq(0)
    expect(query("SELECT count(*) FROM categories")).to be_positive
    expect(output).to include("Home bills kept: 1.")
    expect(query("SELECT name FROM home_bills")).to eq("Energia")
  end

  it "refuses to run in production, and --force outside development" do
    output, status = reset("--force", env: "production")
    expect(status).not_to be_success
    expect(output).to include("HANAMI_ENV is production")

    output, status = reset("--force", env: "test")
    expect(status).not_to be_success
    expect(output).to include("--force is only for HANAMI_ENV=development")
    expect(File.exist?(path)).to be(false)
  end
end
