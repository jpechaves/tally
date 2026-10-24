# frozen_string_literal: true

RSpec.describe "Debug info", type: :request do
  it "shows the SQLite settings in effect" do
    get "/debug"

    expect(last_response.status).to eq(200)
    expect(last_response.body).to include("<h1>Debug info</h1>", %(<a href="/debug" aria-current="page">))
    expect(last_response.body).to include(%(<th scope="row">Journal mode</th><td>wal</td>))
    expect(last_response.body).to include(%(<th scope="row">Foreign keys</th><td>on</td>))
  end

  it "says when foreign keys are off" do
    db = Hanami.app["db.gateway"].connection
    allow(db).to receive(:fetch).and_call_original
    allow(db).to receive(:fetch).with("PRAGMA foreign_keys").and_return(instance_double(Sequel::Dataset, single_value: 0))

    get "/debug"
    expect(last_response.body).to include(%(<th scope="row">Foreign keys</th><td>off</td>))
  end

  describe "database export" do
    it "is off without the login, saying why" do
      get "/debug"
      expect(last_response.body).to include("Export needs the login on")
      expect(last_response.body).not_to include(%(action="/debug/export"))

      post "/debug/export"
      expect(last_response.status).to eq(403)
      expect(last_response.body).to include("Export needs the login on")
    end

    it "downloads a copy of the database when the login is on" do
      allow(Hanami.app["settings"]).to receive_messages(basic_auth_username: "maria", basic_auth_password: "secret")
      allow(Time).to receive(:now).and_return(Time.utc(2026, 10, 24, 15, 0, 0))
      basic_authorize "maria", "secret"

      get "/debug"
      expect(last_response.body).to include(%(action="/debug/export"), "storage/")

      post "/debug/export"
      expect(last_response.status).to eq(200)
      expect(last_response.headers["Content-Disposition"]).to eq(%(attachment; filename="tally-20261024-120000.sqlite"))
      expect(last_response.body).to start_with("SQLite format 3\0")
    end
  end
end
