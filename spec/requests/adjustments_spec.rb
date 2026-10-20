# frozen_string_literal: true

require "fileutils"

RSpec.describe "Adjusting a transaction", :db, type: :request do
  let(:db) { Hanami.app["db.gateway"].connection }
  let(:files) { %w[NU_12345678_01JUL2026_31JUL2026.csv Nubank_2026-07-09.csv Nubank_2026-08-09.csv itau_2026-10.pdf] }

  before do
    allow(Date).to receive(:today).and_return(Date.new(2026, 10, 15))
    files.each { Hanami.app["operations.import_statement"].(file_name: _1, content: fixture(_1)) }
  end

  after { FileUtils.rm_rf(Hanami.app.root.join(Hanami.app["settings"].import_storage_dir)) }

  def row(description) = db[:transactions].where(description:).first

  def food_in_september
    get "/report", month: "2026-09"
    last_response.body[%r{>Food</a></td>\s*<td class="num">R\$ ([\d.,]+)</td>}, 1]
  end

  def adjust(description, **params)
    post "/transactions/#{row(description)[:id]}/adjustment", params
  end

  it "leaves a canceled purchase out of the report, keeping the row as imported" do
    expect(food_in_september).to eq("339.14")
    market = row("MERCADO EXEMPLO")

    adjust("MERCADO EXEMPLO", kind: "canceled", note: "Order never delivered")
    expect(last_response).to be_redirect

    expect(row("MERCADO EXEMPLO")[:amount_cents]).to eq(market[:amount_cents])
    expect(food_in_september).to eq(format("%.2f", (33_914 + market[:amount_cents]) / 100.0))

    get "/transactions/#{market[:id]}"
    expect(last_response.body).to include(%(<span class="badge">canceled</span>), "Order never delivered", "Counts as R$ 0.00")
  end

  it "counts a reimbursed purchase net of what came back, and refuses more than it cost" do
    market = row("MERCADO EXEMPLO")

    adjust("MERCADO EXEMPLO", kind: "reimbursed", amount: "10.00")
    expect(food_in_september).to eq(format("%.2f", (33_914 - 1_000) / 100.0))

    adjust("MERCADO EXEMPLO", kind: "reimbursed", amount: format("%.2f", -market[:amount_cents] / 100.0 + 0.01))
    expect(last_response.location).to end_with("error=invalid_reimbursed_amount")
    expect(food_in_september).to eq(format("%.2f", (33_914 - 1_000) / 100.0))

    get "/transactions", month: "2026-09", kind: "spending", category: db[:categories].where(name: "Alimentação").get(:id).to_s
    expect(last_response.body).to include("spent R$ #{format("%.2f", (33_914 - 1_000) / 100.0)}.", "reimbursed R$ 10.00")
  end

  it "counts the real amount when it changed, with the row's own sign" do
    market = row("MERCADO EXEMPLO")

    adjust("MERCADO EXEMPLO", kind: "amount_changed", amount: "1.00")
    expect(db[:transaction_adjustments].first).to include(kind: "amount_changed", amount_cents: -100)
    expect(food_in_september).to eq(format("%.2f", (33_914 + market[:amount_cents] + 100) / 100.0))

    post "/transactions/#{market[:id]}/adjustment/remove"
    expect(food_in_september).to eq("339.14")
  end

  it "counts a refund row inside the purchase it paid back, and not on its own" do
    purchase = db[:transactions].where(kind: "purchase", account_id: row("CANCELAMENTO PARCIAL DE")[:account_id])
      .where { amount_cents < -6466 }.order(:occurred_on).first
    refund = row("CANCELAMENTO PARCIAL DE")
    get "/transactions/#{purchase[:id]}"
    expect(last_response.body).to include(%(<option value="#{refund[:id]}">))

    post "/transactions/#{purchase[:id]}/adjustment", kind: "reimbursed", refund_id: refund[:id].to_s
    expect(db[:transaction_adjustments].first).to include(amount_cents: 6466, refund_transaction_id: refund[:id])

    rows = Hanami.app["repos.insight_repo"].rows(from: "2026-01", to: "2026-12")
    expect(rows.map { _1[:id] }).not_to include(refund[:id])
    expect(rows.find { _1[:id] == purchase[:id] }).to include(amount_cents: purchase[:amount_cents] + 6466, original_cents: purchase[:amount_cents])

    get "/transactions/#{refund[:id]}"
    expect(last_response.body).to include("counted in a purchase", %(href="/transactions/#{purchase[:id]}?back=))

    post "/transactions/#{refund[:id]}/adjustment", kind: "canceled"
    expect(last_response.location).to end_with("error=not_adjustable")
  end

  it "keeps the adjustment when the statement is imported again" do
    name = "NU_12345678_01JUL2026_31JUL2026.csv"
    purchase = db[:transactions].where(first_import_id: db[:imports].where(file_name: name).get(:id))
      .where { amount_cents < 0 }.exclude(kind: "transfer").order(:id).first
    post "/transactions/#{purchase[:id]}/adjustment", kind: "canceled"

    again = Hanami.app["operations.import_statement"].(file_name: "again-#{name}", content: "#{fixture(name)}\n").value!
    expect(again.status).to eq("applied")

    expect(db[:transactions].where(id: purchase[:id]).get(:last_import_id)).to eq(again.id)
    expect(db[:transaction_adjustments].where(transaction_id: purchase[:id]).get(:kind)).to eq("canceled")
    expect(Hanami.app["repos.insight_repo"].rows(from: "2026-07", to: "2026-07").map { _1[:id] }).not_to include(purchase[:id])
  end

  it "leaves transfers alone" do
    transfer = db[:transactions].where(kind: "transfer").first
    post "/transactions/#{transfer[:id]}/adjustment", kind: "canceled"

    expect(last_response.location).to end_with("error=not_adjustable")
    expect(db[:transaction_adjustments].count).to eq(0)
  end
end
