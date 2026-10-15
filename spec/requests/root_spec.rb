# frozen_string_literal: true

RSpec.describe "Home page", type: :request do
  it "shows the app and the SQLite settings in effect" do
    get "/"

    expect(last_response.status).to eq(200)
    expect(last_response.body).to include("<h1>Tally</h1>")
    expect(last_response.body).to include("<th scope=\"row\">Journal mode</th><td>wal</td>")
    expect(last_response.body).to include("<th scope=\"row\">Foreign keys</th><td>on</td>")
  end
end
