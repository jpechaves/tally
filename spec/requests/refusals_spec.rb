# frozen_string_literal: true

require "fileutils"

# What each form and page does with an id that doesn't exist or input it can't use.
RSpec.describe "Refused requests", :db, type: :request do
  let(:db) { Hanami.app["db.gateway"].connection }
  let(:missing) { 999_999 }

  before do
    allow(Date).to receive(:today).and_return(Date.new(2026, 8, 15))
    name = "NU_12345678_01JUL2026_31JUL2026.csv"
    Hanami.app["operations.import_statement"].call(file_name: name, content: fixture(name))
  end

  after { FileUtils.rm_rf(Hanami.app.root.join(Hanami.app["settings"].import_storage_dir)) }

  def category_id(name) = db[:categories].where(name:).get(:id)

  def row_id(text) = db[:transactions].where(Sequel.like(:raw_description, "%#{text}%")).get(:id)

  def location = last_response.headers["Location"].sub(%r{\Ahttps?://[^/]+}, "")

  it "answers 404 for things that don't exist" do
    [
      [:get, "/counterparties/#{missing}"], [:post, "/counterparties/#{missing}"],
      [:post, "/cuts/#{missing}/restore"], [:get, "/plan/#{missing}"], [:post, "/plan/#{missing}/accept"],
      [:post, "/categories/#{missing}", {name: "Feira"}], [:post, "/transactions/#{missing}"],
      [:post, "/transactions/#{missing}/adjustment", {kind: "canceled"}], [:post, "/transactions/#{missing}/adjustment/remove"]
    ].each do |verb, path, params|
      public_send(verb, path, params || {})
      expect(last_response.status).to eq(404), "#{verb} #{path} answered #{last_response.status}"
    end
    expect(last_response.body).to include(%(<p class="error" role="alert">That is no longer there.</p>), %(<details class="nav-group"))
  end

  it "shows a refusal as a page of the app, in red, with a way back" do
    header "Referer", "http://example.org/trips?page=2"
    post "/trips", name: "Feira", starts_on: "2026-08-10", ends_on: "2026-08-01"

    expect(last_response.status).to eq(422)
    expect(last_response.body).to include(%(<p class="error" role="alert">A trip needs a name, and a first day on or before its last.</p>),
      %(<a href="/trips?page=2">), %(<details class="nav-group"))
  end

  describe "budgets" do
    it "sends a removal for a category that doesn't exist back to its month" do
      post "/budgets/remove", month: "2026-09", category_id: missing
      expect(location).to eq("/budgets?month=2026-09&error=month_and_category")
    end

    it "needs a month to remove budgets from" do
      post "/budgets/remove", all: "1"
      expect(location).to eq("/budgets?error=month_and_category")
    end

    it "refuses a negative limit" do
      post "/budgets", month: "2026-09", category_id: category_id("Delivery"), amount: "-10.00"
      expect(location).to eq("/budgets?month=2026-09&error=invalid_limit")
      expect(db[:budgets].count).to eq(0)
    end
  end

  describe "categories and rules" do
    it "adds a category and goes back to the list" do
      post "/categories", name: "Feira", parent_id: category_id("Alimentação").to_s
      expect(location).to eq("/categories")
      expect(db[:categories].where(name: "Feira").get(:parent_id)).to eq(category_id("Alimentação"))
    end

    it "adds a top-level category of the kind picked" do
      post "/categories", name: "Bicos", parent_id: "", kind: "income"
      expect(location).to eq("/categories")
      expect(db[:categories].where(name: "Bicos").first).to include(parent_id: nil, kind: "income")
    end

    it "says why it couldn't rename a category" do
      post "/categories/#{category_id("Delivery")}", name: " "
      expect(location).to eq("/categories?error=empty_name")
      get location
      expect(last_response.body).to include(%(<p class="error" role="alert">A category needs a name.</p>))
    end

    it "says a rule's amount isn't one" do
      post "/rules", field: "description", operator: "contains", pattern: "feira", category_id: category_id("Delivery"),
        amount_min: "abc"
      expect(location).to eq("/rules?error=invalid_amount")
      expect(db[:category_rules].where(pattern: "feira")).to be_empty
    end
  end

  describe "cut suggestions" do
    it "needs a key to dismiss, and goes back to the cuts page without a month" do
      post "/cuts/dismiss", key: " "
      expect(last_response.status).to eq(422)

      post "/cuts/dismiss", key: "fees:2026-07", title: "Fees"
      expect(location).to eq("/cuts")

      post "/cuts/#{db[:dismissed_suggestions].get(:id)}/restore"
      expect(location).to eq("/cuts")
      expect(db[:dismissed_suggestions].count).to eq(0)
    end
  end

  it "goes back to the imports page when no file was sent" do
    post "/imports"
    expect(location).to eq("/imports")
    post "/imports", files: [{name: "not a file"}]
    expect(location).to eq("/imports")
    expect(db[:imports].count).to eq(1)
  end

  it "refuses a plan limit that isn't an amount" do
    post "/plan", target: "1,000.00", starts_month: "2026-09"
    plan = db[:savings_plans].get(:id)

    post "/plan/#{plan}/accept", proposed: {category_id("Delivery").to_s => "abc"}
    expect(last_response.status).to eq(422)
    expect(db[:savings_plans].where(id: plan).get(:status)).to eq("draft")
  end

  describe "review" do
    it "sets the category on the rows picked, without a rule unless asked" do
      post "/review", ids: row_id("Cobrança exemplo").to_s, category_id: category_id("Lazer"), pattern: "^cobranca", page: "2"

      expect(location).to eq("/review?page=2&saved=1")
      expect(db[:transactions].where(id: row_id("Cobrança exemplo")).get(:category_source)).to eq("manual")
      expect(db[:category_rules].where(origin: "learned")).to be_empty
    end

    it "sets only the rows picked when \"always\" names no payee or pattern" do
      post "/review", ids: row_id("Cobrança exemplo").to_s, category_id: category_id("Lazer"), always: "1",
        counterparty_id: "", pattern: ""

      expect(db[:transactions].where(id: row_id("Cobrança exemplo")).get(:category_source)).to eq("manual")
      expect(db[:category_rules].where(origin: "learned")).to be_empty
    end

    it "learns a rule from the pattern when asked to always use the category" do
      post "/review", ids: row_id("Cobrança exemplo").to_s, category_id: category_id("Lazer"), always: "1", pattern: "^cobranca"

      expect(db[:category_rules].where(origin: "learned").select_map([:pattern, :category_id])).to eq([["^cobranca", category_id("Lazer")]])
      expect(db[:transactions].where(id: row_id("Cobrança exemplo")).get(:category_source)).to eq("rule")
    end

    it "refuses a choice it can't save" do
      post "/review", ids: "", category_id: category_id("Lazer")
      expect(last_response.status).to eq(422)
    end
  end

  describe "a transaction" do
    let(:id) { row_id("Cobrança exemplo") }

    it "says which amount it couldn't read" do
      post "/transactions/#{id}/adjustment", kind: "reimbursed", amount: "abc"
      expect(location).to eq("/transactions/#{id}?error=invalid_reimbursed_amount")

      post "/transactions/#{id}/adjustment", kind: "amount_changed", amount: "abc"
      expect(location).to eq("/transactions/#{id}?error=invalid_adjusted_amount")
    end

    it "refuses a category that doesn't exist" do
      post "/transactions/#{id}", category_id: missing.to_s
      expect(last_response.status).to eq(422)
    end

    it "keeps a category it didn't pick by hand when the form sends none" do
      post "/transactions/#{id}", category_id: category_id("Lazer").to_s, memo: "x"
      db[:transactions].where(id:).update(category_source: "rule")

      post "/transactions/#{id}", memo: ""
      expect(db[:transactions].where(id:).first).to include(category_id: category_id("Lazer"), category_source: "rule", memo: nil)
    end
  end

  describe "pages with nothing to show" do
    it "shows an account's report with no rows" do
      rdb = db[:accounts].where(name: "Nubank RDB").get(:id)
      db[:transactions].where(account_id: rdb).delete

      get "/accounts/#{rdb}/report"
      expect(last_response.status).to eq(200)
    end

    it "shows the transactions of a payee or purchase that has none" do
      get "/transactions", payee: "description:loja inexistente"
      expect(last_response.body).to include("loja inexistente")

      get "/transactions", purchase: row_id("Cobrança exemplo").to_s
      expect(last_response.status).to eq(200)
    end
  end
end

RSpec.describe "Pages with no data", :db, type: :request do
  it "shows the cuts page before anything is imported" do
    get "/cuts"
    expect(last_response.status).to eq(200)
  end
end
