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
end
