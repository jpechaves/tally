# frozen_string_literal: true

require "fileutils"

RSpec.describe "Importing statements", :db, type: :request do
  let(:db) { Hanami.app["db.gateway"].connection }

  after { FileUtils.rm_rf(Hanami.app.root.join(Hanami.app["settings"].import_storage_dir)) }

  def upload(*names)
    files = names.map { Rack::Test::UploadedFile.new(fixture_path(_1).to_s, "application/octet-stream") }
    post "/imports", "files" => files
  end

  it "shows the upload form and an empty history" do
    get "/imports"

    expect(last_response.status).to eq(200)
    expect(last_response.body).to include('enctype="multipart/form-data"', "Nothing imported yet.")
  end

  it "imports one file and shows its result" do
    upload("itau_2026-10.pdf")

    expect(last_response.status).to eq(302)
    follow_redirect!
    expect(last_response.body).to include("itau_2026-10.pdf", "Itaú card (PDF)", "<strong>20</strong> new")
    expect(last_response.body).to include("VOO EXEMPLO*AB12", "8/10 · bought Feb 2, 2026 · viagem · SAO PAULO", "-R$ 1,504.14")
  end

  it "imports several files at once and lists them" do
    upload("NU_12345678_01JUL2026_31JUL2026.csv", "Nubank_2026-07-09.csv")

    expect(last_response.headers["Location"]).to end_with("/imports")
    follow_redirect!
    expect(last_response.body).to include("NU_12345678_01JUL2026_31JUL2026.csv", "Nubank_2026-07-09.csv")
    expect(db[:imports].select_map(:status)).to eq(%w[applied applied])
  end

  it "shows when a file was imported in the local time zone" do
    upload("itau_2026-10.pdf")
    import = db[:imports].get(:id)
    db[:imports].where(id: import).update(created_at: "2026-10-17T22:08:30.123Z")

    get "/imports"
    expect(last_response.body).to include("Oct 17, 2026 19:08")
    get "/imports/#{import}"
    expect(last_response.body).to include("Oct 17, 2026 19:08")

    allow(Hanami.app["settings"]).to receive(:time_zone).and_return(TZInfo::Timezone.get("Europe/Lisbon"))
    get "/imports"
    expect(last_response.body).to include("Oct 17, 2026 23:08")
  end

  it "shows why a file was rejected" do
    post "/imports", "files" => [Rack::Test::UploadedFile.new(StringIO.new("Date,Amount\n"), "text/csv", original_filename: "x.csv")]
    follow_redirect!

    expect(last_response.body).to include("Rejected, nothing was written: unknown file format")
  end

  it "words the importer's errors and warnings in the reader's language" do
    tampered = ItauBills.october.to_pdf.sub("(189,30)", "(189,31)")
    post "/imports", "files" => [Rack::Test::UploadedFile.new(StringIO.new(tampered), "application/pdf", original_filename: "fatura.pdf")]
    rejected = db[:imports].max(:id)
    upload("NU_12345678_01JUL2026_31JUL2026.csv")
    applied = db[:imports].max(:id)

    get "/imports/#{rejected}"
    expect(last_response.body).to include("Rejected, nothing was written: purchases (Lançamentos no cartão): " \
      "the rows add up to R$ 2,609.09, but the bill prints R$ 2,609.08")
    get "/imports/#{applied}"
    expect(last_response.body).to include("line 17: description not recognized, kept as is")

    set_cookie "locale=pt-BR"
    get "/imports/#{rejected}"
    expect(last_response.body).to include("Recusado, nada foi gravado: compras (Lançamentos no cartão): " \
      "os lançamentos somam R$ 2.609,09, mas a fatura imprime R$ 2.609,08")
    get "/imports/#{applied}"
    expect(last_response.body).to include("linha 17: descrição não reconhecida, mantida como está")
  end

  it "shows the English text older imports kept as it is" do
    import = db[:imports].insert(source: "itau_card_pdf", file_name: "old.pdf", file_sha256: "0" * 64, file_size: 1,
      status: "rejected", error: "the PDF has no text pages", warnings: JSON.generate(["an old warning"]))

    get "/imports/#{import}"
    expect(last_response.body).to include("Rejected, nothing was written: the PDF has no text pages", "an old warning")
  end

  it "shows accounts, balances and the bill checks" do
    upload("NU_12345678_01JUL2026_31JUL2026.csv", "Nubank_2026-07-09.csv", "Nubank_2026-08-09.csv")
    get "/accounts"

    expect(last_response.status).to eq(200)
    expect(last_response.body).to include("Nubank RDB", "R$ 1,500.00")
    expect(last_response.body).to match(%r{Jul 9, 2026</td>\s*<td class="num">R\$ 1,765\.75</td>.*paid in full}m)
    expect(last_response.body).to include("payment not imported yet")
  end

  it "lists transactions by account and month" do
    upload("NU_12345678_01JUL2026_31JUL2026.csv")
    account = db[:accounts].where(name: "Nubank conta").get(:id)
    get "/transactions", account:, month: "2026-07"

    expect(last_response.status).to eq(200)
    expect(last_response.body).to include("16 rows", "ENERGIA EXEMPLO S.A.", "transfer ↔ Nubank RDB")
  end

  it "pages the transactions, with the count and net of all of them" do
    stub_const("Tally::Views::Transactions::Index::PER_PAGE", 5)
    upload("NU_12345678_01JUL2026_31JUL2026.csv")
    account = db[:accounts].where(name: "Nubank conta").get(:id)
    net = db[:transactions].where(account_id: account).sum(:amount_cents)
    rows = ->(body) { body.scan(%r{<a href="/transactions/\d+">}).size }

    get "/transactions", account:, month: "2026-07"
    body = last_response.body
    expect(body).to include("16 rows, net #{Tally::Money.new(net).format("en")}", "Page 1 of 4")
    expect(body).to include(%(href="/transactions?account=#{account}&amp;month=2026-07&amp;page=2">Next))
    expect(body).not_to include("Previous")
    expect(rows.(body)).to eq(5)

    get "/transactions", account:, month: "2026-07", page: "4"
    expect(last_response.body).to include("Page 4 of 4", "Previous").and(satisfy { rows.(_1) == 1 })
    expect(last_response.body).not_to include("Next →")

    get "/transactions", account:, month: "2026-07", page: "99"
    expect(last_response.body).to include("Page 4 of 4")
  end

  it "lets you mark yourself, turning a Pix to yourself into a transfer" do
    upload("NU_12345678_01JUL2026_31JUL2026.csv")
    me = db[:counterparties].where(name: "MARIA E SOUZA").get(:id)

    get "/counterparties"
    expect(last_response.body).to include(%(action="/counterparties/#{me}/self"), "This is me")

    post "/counterparties/#{me}/self", is_self: "1"
    expect(last_response.status).to eq(302)
    expect(db[:transactions].where(counterparty_id: me).get(:kind)).to eq("transfer")

    follow_redirect!
    expect(last_response.body).to include("MARIA E SOUZA (you)", "Not me")
  end

  it "strikes through rows that are no longer in the file" do
    upload("Nubank_2026-08-09.csv")
    shorter = fixture("Nubank_2026-08-09.csv").force_encoding("UTF-8").sub(/^2026-07-10.*\n/, "")
    Hanami.app["operations.import_statement"].(file_name: "Nubank_2026-08-09.csv", content: shorter)

    get "/imports/#{db[:imports].max(:id)}"
    expect(last_response.body).to include(%(<tr class="missing">))
    expect(last_response.body).not_to match(/<t[rd][a-z]/)
  end

  it "answers 404 for an unknown import or counterparty" do
    get "/imports/999"
    expect(last_response.status).to eq(404)

    post "/counterparties/999/self", is_self: "1"
    expect(last_response.status).to eq(404)
  end
end
