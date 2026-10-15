# frozen_string_literal: true

require "fileutils"

RSpec.describe "Categorizing", :db, type: :request do
  let(:db) { Hanami.app["db.gateway"].connection }

  before do
    %w[NU_12345678_01JUL2026_31JUL2026.csv itau_2026-10.pdf].each do |name|
      Hanami.app["operations.import_statement"].(file_name: name, content: fixture(name))
    end
  end

  after { FileUtils.rm_rf(Hanami.app.root.join(Hanami.app["settings"].import_storage_dir)) }

  def category_id(name) = db[:categories].where(name:).get(:id)

  def row(description) = db[:transactions].where(description:).first

  it "lists rows to review grouped by payee, with the bank's suggestion" do
    get "/review"

    expect(last_response.status).to eq(200)
    expect(last_response.body).to include("ENERGIA EXEMPLO S.A. · 1 row · -R$ 187,43")
    expect(last_response.body).to include("MERCADO EXEMPLO · 1 row · -R$ 189,30", "the bank suggests Supermercado")
    expect(last_response.body).to include(%(<option value="#{category_id("Supermercado")}" selected>Supermercado</option>))
    expect(last_response.body).not_to include("Pagamento de fatura")
  end

  it "saves a group's category and takes it off the list" do
    energy = db[:counterparties].where(name: "ENERGIA EXEMPLO S.A.").get(:id)
    post "/review", ids: row("ENERGIA EXEMPLO S.A.")[:id].to_s, counterparty_id: energy.to_s,
      category_id: category_id("Energia").to_s, always: "1"

    expect(last_response.status).to eq(302)
    expect(db[:counterparties].where(id: energy).get(:default_category_id)).to eq(category_id("Energia"))
    follow_redirect!
    expect(last_response.body).to include("Saved 1 rows.")
    expect(last_response.body).not_to include("ENERGIA EXEMPLO S.A. ·")
  end

  it "shows a transaction and saves your category and memo" do
    id = row("POSTO EXEMPLO")[:id]
    get "/transactions/#{id}"
    expect(last_response.body).to include("A rule picked Combustível.")

    post "/transactions/#{id}", category_id: category_id("Viagens").to_s, memo: "road trip"
    follow_redirect!
    expect(last_response.body).to include("You picked Viagens.", "road trip")

    post "/transactions/#{id}", category_id: "", memo: ""
    expect(row("POSTO EXEMPLO")).to include(category_source: "rule", category_id: category_id("Combustível"), memo: nil)
  end

  it "shows categories in the transaction list" do
    get "/transactions"

    expect(last_response.body).to include("<td>Combustível</td>", %(<td class="suggested" title="the bank's suggestion">Supermercado?</td>))
    expect(last_response.body).not_to match(/<t[rd][a-z]/)
  end

  it "edits a category's nature and maximum cut, and adds one" do
    get "/categories"
    expect(last_response.body).to include(%(value="Delivery"))

    post "/categories/#{category_id("Delivery")}", name: "Delivery", nature: "essential", max_cut_pct: "20"
    expect(db[:categories].where(name: "Delivery").first).to include(nature: "essential", max_cut_pct: 20)

    post "/categories", name: "Cuidador", parent_id: category_id("Saúde").to_s, nature: "essential"
    expect(db[:categories].where(name: "Cuidador").first).to include(kind: "expense", max_cut_pct: 15)

    post "/categories", name: "Cuidador", parent_id: category_id("Saúde").to_s
    follow_redirect!
    expect(last_response.body).to include("There is already a category with that name there.")

    post "/categories/#{category_id("Cuidador")}", name: "Cuidador", archived: "1"
    get "/categories"
    expect(last_response.body).to include(%(<tr class="missing">))
    expect(last_response.body).not_to match(/<t[rd][a-z]/)
  end

  it "adds and removes a rule" do
    get "/rules"
    expect(last_response.body).to include("description matches regex <code>\\bifood\\b</code>")

    post "/rules", field: "description", operator: "contains", pattern: "pet exemplo",
      category_id: category_id("Pet shop e veterinário").to_s, amount_max: "-1,00", priority: "40"
    expect(row("PET EXEMPLO*PETL")[:category_id]).to eq(category_id("Pet shop e veterinário"))
    rule = db[:category_rules].where(origin: "manual").first
    expect(rule).to include(amount_max_cents: -100, priority: 40, hits: 1)

    post "/rules/#{rule[:id]}/disable"
    expect(row("PET EXEMPLO*PETL")[:category_source]).to eq("none")
    follow_redirect!
    expect(last_response.body).not_to include("pet exemplo")
  end

  it "explains a rule it can't save" do
    post "/rules", field: "description", operator: "regex", pattern: "(oops", category_id: category_id("Lazer").to_s
    follow_redirect!

    expect(last_response.body).to include("That is not a valid regular expression.")
  end

  it "answers 404 for an unknown transaction or rule" do
    get "/transactions/999999"
    expect(last_response.status).to eq(404)

    post "/rules/999999/disable"
    expect(last_response.status).to eq(404)
  end
end
