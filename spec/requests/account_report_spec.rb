# frozen_string_literal: true

require "fileutils"

RSpec.describe "An account's own report", :db, type: :request do
  let(:db) { Hanami.app["db.gateway"].connection }

  before do
    allow(Date).to receive(:today).and_return(Date.new(2026, 10, 15))
    %w[NU_12345678_01JUL2026_31JUL2026.csv conta-global-2026-08.csv].each do |name|
      Hanami.app["operations.import_statement"].(file_name: name, content: fixture(name))
    end
  end

  after { FileUtils.rm_rf(Hanami.app.root.join(Hanami.app["settings"].import_storage_dir)) }

  let(:account_id) { db[:accounts].where(name: "Nubank Conta Global").get(:id) }

  it "shows the dollar account's spending by category and month, in dollars" do
    get "/accounts/#{account_id}/report", month: "2026-07"

    body = last_response.body
    expect(last_response).to be_ok
    expect(body).to include("Nubank Conta Global: where the money went", "US$ 119.95", "Amounts in US$", "nothing here is added to the reais")
    expect(body).not_to match(/R\$ 119[.,]95/)
    expect(body).to include(%(href="/transactions?account=#{account_id}&amp;month=2026-07&amp;kind=spending">US$ 119.95</a>))
    expect(body).to include(%(<a href="/accounts/#{account_id}/report?month=2026-07">Jul 2026</a>))
    expect(body).to include("Loja Exemplo LONDON")
  end

  it "lists the month's top-ups with what they cost in reais" do
    get "/accounts/#{account_id}/report", month: "2026-07"

    body = last_response.body
    # US$ 178.74 for R$ 1,000.00, IOF included; the US$ 50.00 one has no reais leg imported.
    expect(body).to include("US$ 228.74", "paid R$ 1,000.00")
    expect(body).to match(%r{<td class="num">US\$ 178\.74</td>\s*<td class="num">R\$ 1,000\.00</td>\s*<td class="num">5\.5947</td>})
    expect(body).to include("not paired yet")
    expect(body).to include("R$ 5.5947 per US$", "spending was about R$ 671.09.")
  end

  it "has the same numbers as the transactions it links to" do
    get "/transactions", account: account_id.to_s, month: "2026-07", kind: "spending"

    expect(last_response.body).to include("spent US$ 119.95.")
  end

  it "is linked from the accounts page and the main report" do
    get "/accounts"
    expect(last_response.body).to include(%(href="/accounts/#{account_id}/report"))

    get "/report", month: "2026-07"
    expect(last_response.body).to include("Accounts in another currency have their own report:",
      %(<a href="/accounts/#{account_id}/report">Nubank Conta Global</a>.))
  end

  it "works for an account in reais too, without top-ups" do
    nubank = db[:accounts].where(name: "Nubank conta").get(:id)
    get "/accounts/#{nubank}/report", month: "2026-07"

    expect(last_response).to be_ok
    expect(last_response.body).not_to include("Top-ups")
    expect(last_response.body).to include("Amounts in R$; these rows are part of the main report too.")
    expect(last_response.body).not_to include("nothing here is added to the reais")
  end

  it "is a 404 for an account that doesn't exist" do
    get "/accounts/999/report"

    expect(last_response.status).to eq(404)
  end
end
