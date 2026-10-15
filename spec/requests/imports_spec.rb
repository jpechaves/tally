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
    expect(last_response.body).to include("itau_2026-10.pdf", "Itaú cartão (PDF)", "<strong>20</strong> new")
    expect(last_response.body).to include("VOO EXEMPLO*AB12", "8/10 · bought 2026-02-02 · viagem · SAO PAULO", "-R$ 1.504,14")
  end

  it "imports several files at once and lists them" do
    upload("NU_12345678_01JUL2026_31JUL2026.csv", "Nubank_2026-07-09.csv")

    expect(last_response.headers["Location"]).to end_with("/imports")
    follow_redirect!
    expect(last_response.body).to include("NU_12345678_01JUL2026_31JUL2026.csv", "Nubank_2026-07-09.csv")
    expect(db[:imports].select_map(:status)).to eq(%w[applied applied])
  end

  it "shows why a file was rejected" do
    post "/imports", "files" => [Rack::Test::UploadedFile.new(StringIO.new("Date,Amount\n"), "text/csv", original_filename: "x.csv")]
    follow_redirect!

    expect(last_response.body).to include("Rejected, nothing was written: unknown file format")
  end

  it "shows accounts, balances and the bill checks" do
    upload("NU_12345678_01JUL2026_31JUL2026.csv", "Nubank_2026-07-09.csv", "Nubank_2026-08-09.csv")
    get "/accounts"

    expect(last_response.status).to eq(200)
    expect(last_response.body).to include("Nubank RDB", "R$ 1.500,00")
    expect(last_response.body).to match(%r{2026-07-09</td>\s*<td class="num">R\$ 1\.765,75</td>.*paid in full}m)
    expect(last_response.body).to include("payment not imported yet")
  end

  it "lists transactions by account and month" do
    upload("NU_12345678_01JUL2026_31JUL2026.csv")
    account = db[:accounts].where(name: "Nubank conta").get(:id)
    get "/transactions", account:, month: "2026-07"

    expect(last_response.status).to eq(200)
    expect(last_response.body).to include("16 rows", "ENERGIA EXEMPLO S.A.", "transfer ↔ Nubank RDB")
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
