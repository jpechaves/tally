# frozen_string_literal: true

require "fileutils"

RSpec.describe "Filtering transactions", :db, type: :request do
  let(:db) { Hanami.app["db.gateway"].connection }

  before do
    %w[NU_12345678_01JUL2026_31JUL2026.csv Nubank_2026-07-09.csv Nubank_2026-08-09.csv itau_2026-10.pdf
      itau_2027-01_tight.pdf].each do |name|
      Hanami.app["operations.import_statement"].call(file_name: name, content: fixture(name))
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

  it "makes the account, month and category filters searchable, not the kind" do
    get "/transactions"

    body = last_response.body
    expect(body).to include(%(<select name="account" data-picker>), %(<select name="month" data-picker="values">),
      %(<select name="category" data-picker>), %(<select name="kind">), %(<select name="category_id" data-picker required>))
    expect(body).to include(%(<body data-picker-empty="No matches">), %(<script src="/assets/picker.js" defer></script>))

    get "/assets/picker.js"
    expect(last_response.headers["Content-Type"]).to start_with("text/javascript")
    expect(last_response.body).to include("data-picker", "combobox")
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
    # After the last fixture row: the report leaves out rows dated after today.
    allow(Date).to receive(:today).and_return(Date.new(2027, 2, 1))
    %w[NU_12345678_01JUL2026_31JUL2026.csv Nubank_2026-07-09.csv Nubank_2026-08-09.csv itau_2026-10.pdf
      itau_2027-01_tight.pdf].each do |name|
      Hanami.app["operations.import_statement"].call(file_name: name, content: fixture(name))
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

RSpec.describe "Installments link to their purchase", :db, type: :request do
  let(:db) { Hanami.app["db.gateway"].connection }

  before do
    %w[NU_12345678_01JUL2026_31JUL2026.csv Nubank_2026-07-09.csv Nubank_2026-08-09.csv itau_2026-10.pdf
      itau_2027-01_tight.pdf].each do |name|
      Hanami.app["operations.import_statement"].call(file_name: name, content: fixture(name))
    end
  end

  after { FileUtils.rm_rf(Hanami.app.root.join(Hanami.app["settings"].import_storage_dir)) }

  def installment(description, number) = db[:transactions].where(description:, installment_number: number).get(:id)

  def descriptions(body) = body.scan(%r{<a href="/transactions/\d+">([^<]*)</a>}).flatten

  it "shows what is left of each purchase, linked to its installments" do
    allow(Date).to receive(:today).and_return(Date.new(2027, 1, 15))
    get "/installments"

    id = installment("LOJA EXEMPLO", 3)
    expect(last_response.body).to match(%r{<a href="/transactions\?purchase=#{id}">LOJA EXEMPLO</a>.*?7 × R\$ 120\.00 = R\$ 840\.00}m)

    get "/transactions", purchase: id.to_s
    body = last_response.body
    # The 11/12 LOJA EXEMPLO on the other bill is another purchase.
    expect(descriptions(body)).to eq(["LOJA EXEMPLO"])
    expect(body).to include("Purchase: LOJA EXEMPLO (Itaú cartão)")
    expect(body).to include("Installments 3/10. Left to pay from Jan 2027: 7 × R$ 120.00 = R$ 840.00, the last one in Aug 2027.")
  end

  it "lists every installment of a purchase from any one of them" do
    allow(Date).to receive(:today).and_return(Date.new(2026, 8, 15))
    get "/report", month: "2026-07"
    second = installment("Hotel Exemplo", 2)
    expect(last_response.body).to include(%(<a href="/transactions?purchase=#{second}">Hotel Exemplo</a>))

    [second, installment("Hotel Exemplo", 1)].each do |id|
      get "/transactions", purchase: id.to_s
      body = last_response.body
      expect(body.scan(%r{<td class="details">(\d+/6)}).flatten).to eq(%w[2/6 1/6])
      expect(body).to include("2 rows, net -R$ 2,100.00.")
      expect(body).to include("Left to pay from Aug 2026: 4 × R$ 1,050.00 = R$ 4,200.00, the last one in Nov 2026.")
    end
  end

  it "says when a purchase is paid off" do
    allow(Date).to receive(:today).and_return(Date.new(2027, 1, 15))
    get "/transactions", purchase: installment("Hotel Exemplo", 2).to_s

    expect(last_response.body).to include("Installments 2/6: nothing left to pay, the last one was in Nov 2026.")
  end
end

RSpec.describe "Changing categories from the transactions table", :db, type: :request do
  let(:db) { Hanami.app["db.gateway"].connection }

  before do
    %w[Nubank_2026-08-09.csv itau_2026-10.pdf].each do |name|
      Hanami.app["operations.import_statement"].call(file_name: name, content: fixture(name))
    end
  end

  after { FileUtils.rm_rf(Hanami.app.root.join(Hanami.app["settings"].import_storage_dir)) }

  def category_id(name) = db[:categories].where(name:).get(:id)

  def row(description) = db[:transactions].where(description:).first

  it "shows each row's category as a picker, and a box to pick it for a change of many" do
    market = row("MERCADO EXEMPLO")
    get "/transactions", month: "2026-09", page: "1"

    body = last_response.body
    cell = body.scan(%r{<form action="/transactions/category" method="post" class="inline-category">.*?</form>}m)
      .find { _1.include?(%(name="ids[]" value="#{market[:id]}")) }
    expect(cell).to include(%(<input type="hidden" name="month" value="2026-09">), %(<input type="hidden" name="page" value="1">))
    expect(cell).to include(%(<option value="#{market[:category_id]}" selected>Groceries</option>))
    expect(body).to include(%(<input type="checkbox" name="ids[]" value="#{market[:id]}" form="recategorize"))
    expect(body).to match(%r{<form action="/transactions/category" method="post" id="recategorize".*?Change category}m)
    expect(body).to include(%(<script src="/assets/table.js"></script>))

    get "/assets/table.js"
    expect(last_response.body).to include("inline-category", "checkAll", "dataset.ask")
  end

  it "gives the chosen rows a category of your own, back on the same filters and page" do
    ids = [row("MERCADO EXEMPLO"), row("CAFE EXEMPLO")].map { _1[:id].to_s }
    post "/transactions/category", "ids" => ids, "category_id" => category_id("Restaurantes").to_s,
      "month" => "2026-09", "page" => "2"

    expect(last_response.status).to eq(302)
    expect(last_response.location).to eq("/transactions?month=2026-09&page=2&changed=2&skipped=0")
    changed = db[:transactions].where(id: ids.map(&:to_i)).select_map(%i[category_id category_source])
    expect(changed).to all(eq([category_id("Restaurantes"), "manual"]))
    expect(row("SUPERMARKET EX")[:category_id]).to eq(category_id("Supermercado"))
  end

  it "refuses a change with no row or no category" do
    post "/transactions/category", "category_id" => category_id("Restaurantes").to_s
    expect(last_response.status).to eq(422)

    post "/transactions/category", "ids" => [row("CAFE EXEMPLO")[:id].to_s, "x"]
    expect(last_response.status).to eq(422)
  end
end

RSpec.describe "Searching transactions", :db, type: :request do
  let(:db) { Hanami.app["db.gateway"].connection }

  before do
    %w[Nubank_2026-08-09.csv itau_2026-10.pdf].each do |name|
      Hanami.app["operations.import_statement"].call(file_name: name, content: fixture(name))
    end
  end

  after { FileUtils.rm_rf(Hanami.app.root.join(Hanami.app["settings"].import_storage_dir)) }

  def row(description) = db[:transactions].where(description:).first

  def category_id(name) = db[:categories].where(name:).get(:id)

  def found(query, **filters)
    get "/transactions", q: query, **filters
    last_response.body.scan(%r{<a href="/transactions/\d+">([^<]*)</a>}).flatten
  end

  it "finds rows by any of their texts, without accents or case, every word in any order" do
    db[:counterparties].where(id: row("CAFE EXEMPLO")[:counterparty_id]).update(display_name: "Padaria do Bairro")
    db[:counterparties].where(id: row("LIVRARIA EXEMPLO")[:counterparty_id]).update(note: "padaria da esquina")
    db[:transaction_adjustments].insert(transaction_id: row("SUPERMARKET EX")[:id], kind: "canceled", note: "padaria, dividido")
    db[:transactions].where(id: row("POSTO EXEMPLO")[:id]).update(memo: "Pão na padaria")

    expect(found("PADARÍA")).to contain_exactly("PADARIA EXEMPLO", "Padaria do Bairro", "LIVRARIA EXEMPLO", "SUPERMARKET EX", "POSTO EXEMPLO")
    expect(found("bairro padaria")).to eq(["Padaria do Bairro"])
    expect(found("exemplosao")).to contain_exactly("PADARIA EXEMPLO", "MERCADO EXEMPLO", "Padaria do Bairro")
    expect(found("%")).to be_empty
  end

  it "finds rows by amount, of either sign unless one is typed, as imported or as adjusted" do
    db[:transaction_adjustments].insert(transaction_id: row("POSTO EXEMPLO")[:id], kind: "amount_changed", amount_cents: -12_000)

    expect(found("32,90")).to contain_exactly("LIVRARIA EXEMPLO", "CANCELAMENTO DE COMPRA")
    expect(found("R$ 32.90")).to contain_exactly("LIVRARIA EXEMPLO", "CANCELAMENTO DE COMPRA")
    expect(found("-32,90")).to eq(["LIVRARIA EXEMPLO"])
    expect(found("+32,90")).to eq(["CANCELAMENTO DE COMPRA"])
    expect(found("32")).to be_empty
    expect(found("120")).to eq(["POSTO EXEMPLO"])
    expect(found("150,00")).to eq(["POSTO EXEMPLO"])
  end

  it "combines with the other filters, and keeps the search in the form and in changes made from the table" do
    expect(found("exemplo", month: "2026-09", category: "none")).to contain_exactly("MARKETPLACE*EXEMPLO", "PET EXEMPLO*PETL", "ASSINATURA EXEMPLO")

    body = last_response.body
    expect(body).to include(%(<input type="search" name="q" value="exemplo" placeholder="Search description, note or amount"))
    expect(body).to include("3 rows, net", %(<a href="/transactions?month=2026-09&amp;category=none">Clear search</a>))
    expect(body).to include(%(<input type="hidden" name="q" value="exemplo">))
    expect(body).to include(%(<input type="checkbox" name="all" value="1" data-check-all="recategorize"> Select all 3 results))
    expect(body).to include(%(data-ask="Change the category of %{rows} to %{category}?"))

    get "/transactions", q: "nada assim"
    expect(last_response.body).to include("No transactions match these filters.")

    get "/transactions"
    expect(last_response.body).not_to include("Clear search", "Select all")
  end

  it "changes the category of every row the filters find, on every page, skipping transfers" do
    db[:transactions].where(id: row("Pagamento via conta")[:id]).update(memo: "estacionamento")
    parking = db[:transactions].where(description: "ESTACIONAMENTO EXEMPLO").select_map(:id)

    post "/transactions/category", "all" => "1", "q" => "estacionamento", "category_id" => category_id("Restaurantes").to_s, "page" => "1"

    expect(last_response.location).to eq("/transactions?q=estacionamento&page=1&changed=2&skipped=1")
    expect(db[:transactions].where(id: parking).select_map(%i[category_id category_source])).to all(eq([category_id("Restaurantes"), "manual"]))
    expect(row("Pagamento via conta")[:category_id]).to be_nil

    follow_redirect!
    expect(last_response.body).to include("Changed the category of 2 rows. 1 transfer left as it was: transfers have no category.")
  end

  it "refuses to change every row when nothing narrows them" do
    expect {
      post "/transactions/category", "all" => "1", "category_id" => category_id("Restaurantes").to_s
    }.not_to change { db[:transactions].where(category_id: category_id("Restaurantes")).count }

    expect(last_response.status).to eq(422)
  end
end
