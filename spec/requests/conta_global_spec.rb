# frozen_string_literal: true

require "fileutils"

RSpec.describe "The dollar account", :db, type: :request do
  let(:db) { Hanami.app["db.gateway"].connection }

  before do
    %w[NU_12345678_01JUL2026_31JUL2026.csv conta-global-2026-08.csv].each do |name|
      Hanami.app["operations.import_statement"].call(file_name: name, content: fixture(name))
    end
  end

  after { FileUtils.rm_rf(Hanami.app.root.join(Hanami.app["settings"].import_storage_dir)) }

  def account_id(name) = db[:accounts].where(name:).get(:id)

  it "lists its rows in dollars, with the exchange and the fee" do
    get "/transactions", account: account_id("Nubank Conta Global").to_s

    body = last_response.body
    expect(body).to include("10 rows.", "Balance<strong>US$ 113.04</strong>")
    expect(body).to include("-US$ 52.84", "GBP 41.20 · fee US$ 0.19")
  end

  it "never adds dollars to reais" do
    get "/transactions", month: "2026-07"

    expect(last_response.body).to match(%r{Balance<strong>R\$ [\d,.]+ \+ US\$ 108\.79</strong>})
  end

  it "shows the account's balance in dollars" do
    get "/accounts"

    expect(last_response.body).to include("US$ 113.04")
  end

  it "keeps its spending out of the report, which is in reais" do
    get "/report", month: "2026-07"

    body = last_response.body
    expect(body).not_to include("Loja Exemplo LONDON", "Mercado Exemplo ORLANDO")
  end
end
