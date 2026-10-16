# frozen_string_literal: true

require "fileutils"

RSpec.describe "Filtering transactions", :db, type: :request do
  let(:db) { Hanami.app["db.gateway"].connection }

  before do
    %w[NU_12345678_01JUL2026_31JUL2026.csv Nubank_2026-07-09.csv Nubank_2026-08-09.csv itau_2026-10.pdf
      itau_2027-01_tight.pdf].each do |name|
      Hanami.app["operations.import_statement"].(file_name: name, content: fixture(name))
    end
  end

  after { FileUtils.rm_rf(Hanami.app.root.join(Hanami.app["settings"].import_storage_dir)) }

  def category_id(name) = db[:categories].where(name:).get(:id)

  def descriptions(body) = body.scan(%r{<a href="/transactions/\d+">([^<]*)</a>}).flatten

  it "shows one category's rows in a month, with their total" do
    get "/transactions", category: category_id("Supermercado").to_s, month: "2026-09"

    body = last_response.body
    expect(descriptions(body)).to contain_exactly("MERCADO EXEMPLO", "SUPERMARKET EX")
    expect(body).to include("2 rows, net -R$ 247.84.")
    expect(body).to include(%(<option value="#{category_id("Supermercado")}" selected>Groceries</option>))
  end

  it "takes in a parent category's children" do
    get "/transactions", category: category_id("Alimentação").to_s, month: "2026-09"

    expect(descriptions(last_response.body)).to contain_exactly("MERCADO EXEMPLO", "SUPERMARKET EX", "CAFE EXEMPLO")
  end

  it "shows the rows with no category" do
    get "/transactions", category: "none", month: "2026-09", kind: "spending"

    body = last_response.body
    expect(descriptions(body)).to contain_exactly("MARKETPLACE*EXEMPLO", "PET EXEMPLO*PETL", "CANCELAMENTO PARCIAL DE", "ASSINATURA EXEMPLO")
    expect(body).to include(%(<option value="none" selected>No category</option>))
  end

  it "totals spending the way the report does" do
    get "/transactions", category: category_id("Alimentação").to_s, month: "2026-09", kind: "spending"
    expect(last_response.body).to include("3 rows, spent R$ 339.14.")

    get "/report", month: "2026-09"
    expect(last_response.body).to match(%r{<td>Food</td>\s*<td class="num">R\$ 339\.14</td>})
  end

  it "keeps the filters across pages" do
    stub_const("Tally::Views::Transactions::Index::PER_PAGE", 1)
    get "/transactions", category: category_id("Supermercado").to_s, month: "2026-09"

    expect(last_response.body).to include(
      %(href="/transactions?month=2026-09&amp;category=#{category_id("Supermercado")}&amp;page=2">Next)
    )
  end
end
