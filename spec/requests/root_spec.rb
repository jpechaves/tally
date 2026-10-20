# frozen_string_literal: true

require "fileutils"

RSpec.describe "Home page", type: :request do
  it "shows the app, with its sidebar sections open and the SQLite settings left to the debug page" do
    get "/"

    expect(last_response.status).to eq(200)
    expect(last_response.body).to include("<h1>Overview</h1>", %(<link rel="stylesheet" href="/assets/app.css">))
    expect(last_response.body).to include(%(<details class="nav-group" data-group="overview" open>), %(<summary>Overview</summary>))
    expect(last_response.body).to include(%(<a href="/" aria-current="page">Home</a>), %(<a href="/debug">))
    expect(last_response.body).not_to include("Journal mode")
  end

  it "serves the stylesheet, and nothing else from the assets folder by name" do
    get "/assets/app.css"
    expect(last_response.status).to eq(200)
    expect(last_response.headers["Content-Type"]).to start_with("text/css")
    expect(last_response.body).to include("--accent: #5e6ad2")

    get "/assets/sidebar.js"
    expect(last_response.headers["Content-Type"]).to start_with("text/javascript")

    get "/assets/other.css"
    expect(last_response.status).to eq(404)
  end

  context "with statements imported", :db do
    before do
      allow(Date).to receive(:today).and_return(Date.new(2026, 8, 15))
      %w[NU_12345678_01JUL2026_31JUL2026.csv Nubank_2026-07-09.csv Nubank_2026-08-09.csv].each do |name|
        Hanami.app["operations.import_statement"].call(file_name: name, content: fixture(name))
      end
    end

    after { FileUtils.rm_rf(Hanami.app.root.join(Hanami.app["settings"].import_storage_dir)) }

    it "shows the latest complete month, the trend by month and where the money went" do
      get "/"
      body = last_response.body

      expect(body).to include("Showing Jul 2026, the latest complete month.", "Income<strong>R$ 8,920.00</strong>")
      expect(body).to include(%(role="img" aria-label="Income and spending by month"), "<title>Jul 2026 · Income: R$ 8,920.00</title>")
      expect(body).to include(%(class="current">Jul 2026</text>), ">R$ 9K</text>")
      expect(body).to match(%r{<dt>Transfers</dt>\s*<dd title="R\$ [\d,.]+ · [\d.]+%"><div class="bar" style="width: 100.0%"></div></dd>})
    end

    it "words the axis in Portuguese" do
      set_cookie "locale=pt-BR"
      get "/"

      expect(last_response.body).to include(">R$ 9 mil</text>", "<title>jul/2026 · Receitas: R$ 8.920,00</title>")
    end
  end
end
