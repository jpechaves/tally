# frozen_string_literal: true

require "fileutils"

# Issue #87: a breadcrumb on every page below a section, back to the page you came from
# (?back=) with its filters and page, or to the section when you came from nowhere.
RSpec.describe "Breadcrumbs", :db, type: :request do
  let(:db) { Hanami.app["db.gateway"].connection }
  let(:delivery) { db[:categories].where(name: "Delivery").get(:id) }
  let(:ifood) { db[:transactions].where(description: "iFood").get(:id) }
  let(:energy) { db[:transactions].exclude(counterparty_id: nil).get(%i[id counterparty_id]) }

  before do
    allow(Date).to receive(:today).and_return(Date.new(2026, 10, 15))
    %w[NU_12345678_01JUL2026_31JUL2026.csv Nubank_2026-08-09.csv].each do |name|
      Hanami.app["operations.import_statement"].call(file_name: name, content: fixture(name))
    end
  end

  after { FileUtils.rm_rf(Hanami.app.root.join(Hanami.app["settings"].import_storage_dir)) }

  def url(path) = Rack::Utils.escape(path)

  # The breadcrumb's links and the current page, as [[label, href], ..., [label, nil]].
  def crumbs
    nav = last_response.body[%r{<nav class="breadcrumb".*?</nav>}m] or return []
    nav.scan(%r{<a href="([^"]*)">([^<]*)</a>|<span aria-current="page">([^<]*)</span>}).map do |href, label, current|
      current ? [current, nil] : [label, CGI.unescapeHTML(href)]
    end
  end

  it "goes back from a transaction to the filtered list and page it was opened from" do
    list = "/transactions?month=2026-07&category=#{delivery}&page=1"
    get list
    expect(last_response.body).to include(%(href="/transactions/#{ifood}?back=#{url(list)}"))

    get "/transactions/#{ifood}", back: list
    expect(crumbs).to eq([["Transactions (Food delivery, Jul 2026)", list], ["iFood", nil]])
    here = "/transactions/#{ifood}?back=#{url(list)}"
    expect(last_response.body).to include(%(<input type="hidden" name="back" value="#{CGI.escapeHTML(list)}">))

    post "/transactions/#{ifood}", memo: "weekly shop", back: list
    expect(last_response.location).to end_with(here)
    post "/transactions/#{ifood}/adjustment", kind: "canceled", back: list
    expect(last_response.location).to end_with(here)
    post "/transactions/#{ifood}/adjustment", kind: "different", amount: "x", back: list
    expect(last_response.location).to end_with("/transactions/#{ifood}?error=invalid_adjusted_amount&back=#{url(list)}")
    post "/transactions/#{ifood}/adjustment/remove", back: list
    expect(last_response.location).to end_with(here)
  end

  it "uses the section when the way back is missing, or isn't a page of this app" do
    get "/transactions/#{ifood}", back: "//example.com/x"
    expect(crumbs).to eq([["Transactions", "/transactions"], ["iFood", nil]])

    get "/counterparties/#{energy[1]}"
    expect(crumbs.first).to eq(["Counterparties", "/counterparties"])
  end

  it "goes back from a counterparty to the transaction that linked to it" do
    get "/transactions/#{energy[0]}"
    link = "/counterparties/#{energy[1]}?back=#{url("/transactions/#{energy[0]}")}"
    expect(last_response.body).to include(%(href="#{link}"))

    get link
    expect(crumbs.first).to eq(["Transaction", "/transactions/#{energy[0]}"])
  end

  it "keeps the page that sent you to a filtered list through its filters, pages and category changes" do
    get "/report", month: "2026-07"
    link = "/transactions?month=2026-07&category=#{delivery}&kind=spending&back=#{url("/report?month=2026-07")}"
    expect(last_response.body).to include(%(href="#{CGI.escapeHTML(link)}"))

    get link
    expect(crumbs).to eq([["Report", "/report?month=2026-07"], ["Transactions", nil]])
    expect(last_response.body).to include(%(<input type="hidden" name="back" value="/report?month=2026-07">))

    post "/transactions/category", ids: [ifood.to_s], category_id: delivery.to_s, month: "2026-07", page: "1", back: "/report?month=2026-07"
    expect(last_response.location).to include("back=#{url("/report?month=2026-07")}")
  end

  it "shows the section above the pages that have a fixed one" do
    trip = db[:trips].insert(name: "Praia, jul/2026", starts_on: "2026-07-01", ends_on: "2026-07-10")
    account = db[:accounts].get(:id)
    import = db[:imports].get(:id)

    {"/trips/#{trip}" => ["Trips", "/trips"], "/accounts/#{account}/report" => ["Accounts", "/accounts"],
     "/imports/#{import}" => ["Import", "/imports"], "/subscriptions" => ["Cuts", "/cuts"]}.each do |page, parent|
      get page
      expect(crumbs.first).to eq(parent)
    end
  end
end
