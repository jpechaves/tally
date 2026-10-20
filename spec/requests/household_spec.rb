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

    post "/counterparties/#{party("MARIA E SOUZA")}/self", person: me_id.to_s
    get "/transactions", kind: "unmatched"
    expect(last_response.body).to include("Transfers between you with no other side", "-R$ 80.00")
    expect(last_response.body).not_to include("-R$ 150.00")

    post "/counterparties/#{jose}/self", person: ""
    expect(db[:counterparties].where(id: jose).get(%i[is_self person_id])).to eq([0, nil])
  end
end
