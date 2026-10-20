# frozen_string_literal: true

require "fileutils"

# Issue #37: your own name and note for a counterparty.
RSpec.describe "Counterparty names", :db, type: :request do
  let(:db) { Hanami.app["db.gateway"].connection }
  let(:file) { "NU_12345678_01JUL2026_31JUL2026.csv" }
  let(:energy) { db[:counterparties].where(name: "ENERGIA EXEMPLO S.A.").get(:id) }
  let(:row) { db[:transactions].where(counterparty_id: energy).get(:id) }

  def import(content = fixture(file)) = Hanami.app["operations.import_statement"].call(file_name: file, content:)

  before do
    allow(Date).to receive(:today).and_return(Date.new(2026, 10, 15))
    import
  end

  after { FileUtils.rm_rf(Hanami.app.root.join(Hanami.app["settings"].import_storage_dir)) }

  def name_it(display_name = "Conta de luz", note = "the flat's power bill", back: nil)
    post "/counterparties/#{energy}", {display_name:, note:, back:}.compact
  end

  it "saves the name and note and goes back where it was asked from" do
    get "/counterparties/#{energy}", back: "/review?page=1"
    expect(last_response.body).to include("At the bank: ENERGIA EXEMPLO S.A.", %(name="back" value="/review?page=1"))

    name_it(back: "/review?page=1")
    expect(last_response.headers["Location"]).to end_with("/review?page=1")
    expect(db[:counterparties].where(id: energy).get(%i[display_name note])).to eq(["Conta de luz", "the flat's power bill"])
  end

  it "keeps the first 200 characters of the name and 500 of the note" do
    name_it("n" * 201, "x" * 501)

    expect(db[:counterparties].where(id: energy).get(%i[display_name note])).to eq(["n" * 200, "x" * 500])
  end

  it "never sends you to another site" do
    name_it(back: "//example.com/x")
    expect(last_response.headers["Location"]).to end_with("/counterparties/#{energy}")
  end

  it "shows the name on the counterparties, review, report and transactions, with the bank's name kept" do
    name_it

    get "/counterparties"
    expect(last_response.body).to include(%(<span class="name">Conta de luz</span>), "ENERGIA EXEMPLO S.A.", "the flat&#39;s power bill")
    expect(last_response.body).to include(%(href="/transactions?payee=counterparty%3A#{energy}"))

    get "/review"
    expect(last_response.body).to include("Conta de luz · 1 row")

    get "/report", month: "2026-07"
    expect(last_response.body).to include("Conta de luz")

    get "/transactions", payee: "counterparty:#{energy}"
    expect(last_response.body).to include("Payee: Conta de luz", %(">Conta de luz</a>), "the flat&#39;s power bill")

    get "/transactions/#{row}"
    expect(last_response.body).to include("Counterparty: Conta de luz", "(ENERGIA EXEMPLO S.A.)")
  end

  it "finds a counterparty by either name" do
    name_it

    ["conta de luz", "energia exemplo"].each do |query|
      get "/counterparties", q: query
      expect(last_response.body).to include("1 counterparty", %(<span class="name">Conta de luz</span>))
    end
  end

  it "shows the bank's name again when the name is cleared" do
    name_it
    name_it("  ", "")

    expect(db[:counterparties].where(id: energy).get(%i[display_name note])).to eq([nil, nil])
    get "/review"
    expect(last_response.body).to include("ENERGIA EXEMPLO S.A. · 1 row")
  end

  it "keeps the name and note when the file is imported again" do
    name_it
    import(fixture(file) + "\n")

    expect(db[:counterparties].where(id: energy).get(%i[name display_name note]))
      .to eq(["ENERGIA EXEMPLO S.A.", "Conta de luz", "the flat's power bill"])
  end

  it "keeps rules matching the bank's name" do
    name_it
    category = db[:categories].where(name: "Energia").get(:id)
    Hanami.app["operations.save_rule"].call(field: "counterparty_name", operator: "contains", pattern: "ENERGIA EXEMPLO", category_id: category)

    expect(db[:transactions].where(id: row).get(:category_id)).to eq(category)
  end
end
