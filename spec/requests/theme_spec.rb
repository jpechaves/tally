# frozen_string_literal: true

RSpec.describe "Themes", type: :request do
  it "follows the system's light or dark setting until one is picked" do
    get "/"
    expect(last_response.body).to include(%(<html lang="en" data-theme="system">), %(<meta name="color-scheme" content="dark light">))
    expect(last_response.body).to include(%(name="theme" value="light"), %(name="theme" value="dark"))
    expect(last_response.body).not_to include(%(value="system"))
  end

  it "switches to the light theme and back, remembering the choice in a cookie" do
    post "/theme", theme: "light", back: "/report?month=2026-07"
    expect(last_response.status).to eq(302)
    expect(last_response.headers["Location"]).to end_with("/report?month=2026-07")
    expect(last_response.headers["Set-Cookie"]).to include("theme=light", "samesite=lax")

    follow_redirect!
    expect(last_response.body).to include(%(<html lang="en" data-theme="light">))

    post "/theme", theme: "dark"
    expect(last_response.headers["Location"]).to end_with("/")
    follow_redirect!
    expect(last_response.body).to include(%(<html lang="en" data-theme="dark">))
  end

  it "goes back to following the system, forgetting the choice" do
    post "/theme", theme: "light"
    follow_redirect!
    expect(last_response.body).to include(%(name="theme" value="system"))

    post "/theme", theme: "system", back: "/budgets"
    expect(last_response.headers["Location"]).to end_with("/budgets")
    expect(last_response.headers["Set-Cookie"]).to match(/theme=;.*max-age=0/i)

    follow_redirect!
    expect(last_response.body).to include(%(<html lang="en" data-theme="system">))
  end

  it "refuses an unknown theme" do
    post "/theme", theme: "sepia"
    expect(last_response.status).to eq(422)
  end
end
