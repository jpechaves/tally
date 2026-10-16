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
    expect(last_response.body).to match(%r{>Food</a></td>\s*<td class="num">R\$ 339\.14</td>})
  end

  it "keeps the filters across pages" do
    stub_const("Tally::Views::Transactions::Index::PER_PAGE", 1)
    get "/transactions", category: category_id("Supermercado").to_s, month: "2026-09"

    expect(last_response.body).to include(
      %(href="/transactions?month=2026-09&amp;category=#{category_id("Supermercado")}&amp;page=2">Next)
    )
  end
end

RSpec.describe "Report rows link to their transactions", :db, type: :request do
  before do
    %w[NU_12345678_01JUL2026_31JUL2026.csv Nubank_2026-07-09.csv Nubank_2026-08-09.csv itau_2026-10.pdf
      itau_2027-01_tight.pdf].each do |name|
      Hanami.app["operations.import_statement"].(file_name: name, content: fixture(name))
    end
  end

  after { FileUtils.rm_rf(Hanami.app.root.join(Hanami.app["settings"].import_storage_dir)) }

  # Each line of the report's tables: [link, amount, rows].
  def report_lines(body)
    body.scan(%r{<td><a href="(/transactions\?[^"]+)">[^<]*</a></td>\s*<td class="num">([^<]*)</td>.*?<td class="num">(\d+)</td>\s*</tr>}m)
  end

  it "links each category, nature and payee to rows that add up to it, in every month" do
    months = Hanami.app["repos.transaction_repo"].months
    checked = months.sum do |month|
      get "/report", month: month
      lines = report_lines(last_response.body)
      expect(lines).not_to be_empty

      lines.each do |href, amount, rows|
        get CGI.unescapeHTML(href)
        expect([href, last_response.body]).to match([href, include("#{rows} row#{"s" unless rows == "1"}, spent #{amount}.")])
      end
      lines.size
    end
    expect(checked).to be > 50
  end

  it "links a payee to all its rows, its name variants included" do
    get "/report", month: "2026-12"
    href = last_response.body[%r{<a href="([^"]+)">RESTAURANTE EXEMPLO</a>}, 1]
    expect(href).to include("payee=counterparty")

    get CGI.unescapeHTML(href)
    body = last_response.body
    expect(body).to include("2 rows, spent R$ 460.00.", %(<span class="badge">Payee: RESTAURANTE EXEMPLO))
    expect(body).to include(%(<input type="hidden" name="payee" value="counterparty:))
    expect(body).to include(%(href="/transactions?month=2026-12&amp;kind=spending" title="Remove this filter"))
  end

  it "links rows paid without a counterparty by their description" do
    get "/transactions", payee: "description:cobranca exemplo com virgula"
    expect(last_response.body).to include("1 row, net -R$ 12.34.", "Payee: Cobrança exemplo, com vírgula")
  end

  it "links a nature, including rows with none" do
    get "/transactions", nature: "unset", month: "2026-09", kind: "spending"
    expect(last_response.body).to include("Nature: no nature")

    get "/transactions", nature: "fixed", month: "2026-09"
    expect(last_response.body).to include("2 rows, net -R$ 52.50.", "Nature: fixed")
  end
end
