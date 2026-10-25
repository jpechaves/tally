# frozen_string_literal: true

require "fileutils"

RSpec.describe "The household", :db, type: :request do
  let(:db) { Hanami.app["db.gateway"].connection }

  after { FileUtils.rm_rf(Hanami.app.root.join(Hanami.app["settings"].import_storage_dir)) }

  def upload(name, **params)
    post "/imports", "files" => [Rack::Test::UploadedFile.new(fixture_path(name).to_s, "application/octet-stream")], **params
  end

  def party(name) = db[:counterparties].where(name:).get(:id)

  it "adds and renames people on the accounts page, and refuses a blank or repeated name" do
    get "/accounts"
    expect(last_response.body).to include(%(id="people"), %(value="Eu"), "(you)")

    post "/people", name: " Bruno "
    expect(last_response.headers["Location"]).to end_with("/accounts#people")
    bruno = db[:people].where(name: "Bruno").get(:id)

    post "/people/#{bruno}", name: "Beto"
    expect(db[:people].where(id: bruno).get(:name)).to eq("Beto")

    post "/people", name: "Beto"
    expect(last_response.status).to eq(422)
    expect(last_response.body).to include("A person needs a name no one else in the household has.")
    post "/people/#{bruno}", name: " "
    expect(last_response.status).to eq(422)
    post "/people/999", name: "Ana"
    expect(last_response.status).to eq(404)
  end

  it "imports someone else's statements as theirs, and marks who a counterparty is" do
    upload("NU_12345678_01JUL2026_31JUL2026.csv")
    get "/imports"
    expect(last_response.body).not_to include(%(name="person"))

    post "/people", name: "Bruno"
    bruno = db[:people].where(name: "Bruno").get(:id)
    get "/imports"
    expect(last_response.body).to include("Whose statements:", %(<option value="#{bruno}">Bruno</option>))
    upload("NU_87654321_01JUL2026_31JUL2026.csv", person: bruno.to_s)
    expect(db[:accounts].where(name: "Nubank conta (Bruno)").get(:person_id)).to eq(bruno)

    jose = party("JOSE DA SILVA EXEMPLO")
    post "/counterparties/#{jose}/self", person: bruno.to_s
    get "/counterparties"
    expect(last_response.body).to include("JOSE DA SILVA EXEMPLO</span> (Bruno)", %(<option value="#{bruno}" selected>Bruno</option>))
    expect(last_response.body).to include("Pick who in the household each name is")
    expect(last_response.body).not_to include("This is me")

    post "/counterparties/#{party("MARIA E SOUZA")}/self", person: me_id.to_s
    get "/transactions", kind: "unmatched"
    expect(last_response.body).to include("Transfers between you with no other side", "-R$ 80.00")
    expect(last_response.body).not_to include("-R$ 150.00")

    post "/counterparties/#{jose}/self", person: ""
    expect(db[:counterparties].where(id: jose).get(%i[is_self person_id])).to eq([0, nil])
  end

  # Issue #164: a Pix with only a name can be someone of the household too; a card or
  # debit merchant can't.
  it "offers who it is on a name-only Pix counterparty, in Contrapartes and in Revisar" do
    Hanami.app["operations.import_statement"].call(file_name: "NU_11112222_01AUG2026_31AUG2026.csv", content: <<~CSV)
      Data,Valor,Identificador,Descrição
      16/08/2026,-1000.00,b1b2c3d4-0000-4000-8000-000000000001,Transferência enviada pelo Pix - BRUNO EXEMPLO DA SILVA (Transferência enviada)
      17/08/2026,-20.00,b1b2c3d4-0000-4000-8000-000000000002,Compra no débito - PADARIA EXEMPLO
    CSV
    name_only = db[:counterparties].where(Sequel.like(:name, "BRUNO EXEMPLO%")).get(:id)
    bakery = party("PADARIA EXEMPLO")

    get "/counterparties"
    expect(last_response.body).to include(%(action="/counterparties/#{name_only}/self"))
    expect(last_response.body).not_to include(%(action="/counterparties/#{bakery}/self"))

    get "/review"
    expect(last_response.body).to include(%(action="/counterparties/#{name_only}/self"), %(name="back" value="/review?page=1"))
    expect(last_response.body).not_to include(%(action="/counterparties/#{bakery}/self"))

    post "/counterparties/#{name_only}/self", person: me_id.to_s, back: "/review?page=1"
    expect(last_response.headers["Location"]).to end_with("/review?page=1")
    expect(db[:transactions].where(counterparty_id: name_only).get(:kind)).to eq("transfer")
  end

  describe "the person switch" do
    let(:bruno) { db[:people].where(name: "Bruno").get(:id) }

    before do
      upload("NU_12345678_01JUL2026_31JUL2026.csv")
      post "/people", name: "Bruno"
      upload("NU_87654321_01JUL2026_31JUL2026.csv", person: bruno.to_s)
      post "/counterparties/#{party("JOSE DA SILVA EXEMPLO")}/self", person: bruno.to_s
      post "/counterparties/#{party("MARIA E SOUZA")}/self", person: me_id.to_s
    end

    def spending = last_response.body[%r{Spending<strong>([^<]+)</strong>}, 1]

    it "adds up the household, or one person, leaving out the Pix between them" do
      get "/report", month: "2026-07"
      expect(spending).to eq("R$ 1,236.72")
      expect(last_response.body).to include(%(<a href="/report?month=2026-07" aria-current="page">Household</a>),
        %(<a href="/report?month=2026-07&amp;person=#{bruno}">Bruno</a>), "1 transfer between people of the household has no other side")

      get "/report", month: "2026-07", person: me_id.to_s
      expect(spending).to eq("R$ 954.22")
      expect(last_response.body).to include(%(<input type="hidden" name="person" value="#{me_id}">))

      get "/report", month: "2026-07", person: bruno.to_s
      expect(spending).to eq("R$ 282.50")
      expect(last_response.body).to include("/transactions?person=#{bruno}&amp;month=2026-07&amp;kind=spending")

      get "/transactions", person: bruno.to_s, month: "2026-07", kind: "spending"
      expect(last_response.body).to include("Person: Bruno", "SUPERMERCADO EXEMPLO")
      expect(last_response.body).not_to include("ENERGIA EXEMPLO")
      get "/transactions", person: "999"
      expect(last_response.body).to include("Person: 999", "No transactions match these filters.")
    end

    it "switches Home, Cuts and Budgets too, with the household's budgets and only its plan's target" do
      get "/", person: bruno.to_s
      expect(last_response.body).to include(%(aria-current="page">Bruno</a>), "/report?month=2026-07&amp;person=#{bruno}")

      get "/cuts", month: "2026-07", person: bruno.to_s
      expect(last_response.body).to include(%(aria-current="page">Bruno</a>))

      db[:savings_plans].insert(target_cents: 50_000, baseline_from: "2026-04", baseline_to: "2026-06", baseline_income_cents: 900_000,
        baseline_spending_cents: 100_000, starts_month: "2026-09", status: "active")
      db[:budgets].insert(category_id: db[:categories].insert(name: "Mercado", kind: "expense"), month: "2026-09", amount_cents: 60_000)
      get "/budgets", month: "2026-09"
      expect(last_response.body).to include("Target<strong>R$ 500.00</strong>")
      get "/budgets", month: "2026-09", person: bruno.to_s
      expect(last_response.body).to include(%(aria-current="page">Bruno</a>))
      expect(last_response.body).not_to include("Target<strong>")
    end
  end
end
