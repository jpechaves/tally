# frozen_string_literal: true

require "fileutils"

RSpec.describe "Savings plan and budgets", :db, type: :request do
  let(:db) { Hanami.app["db.gateway"].connection }

  before do
    allow(Date).to receive(:today).and_return(Date.new(2026, 8, 15))
    %w[NU_12345678_01JUL2026_31JUL2026.csv Nubank_2026-07-09.csv Nubank_2026-08-09.csv].each do |name|
      Hanami.app["operations.import_statement"].(file_name: name, content: fixture(name))
    end
  end

  after { FileUtils.rm_rf(Hanami.app.root.join(Hanami.app["settings"].import_storage_dir)) }

  def category_id(name) = db[:categories].where(name:).get(:id)

  it "plans from the last three complete months, and accepting writes the budgets" do
    get "/plan"
    expect(last_response.body).to include(%(<option value="2026-09" selected>))

    post "/plan", target: "2,500.00", starts_month: "2026-09"
    plan = db[:savings_plans].first
    expect(plan).to include(status: "draft", baseline_from: "2026-05", baseline_to: "2026-07", target_cents: 250_000)
    expect(last_response.headers["Location"]).to end_with("/plan/#{plan[:id]}")

    follow_redirect!
    body = last_response.body
    expect(body).to include("Save R$ 2,500.00 a month", "Transferências (Pix)", %(name="proposed[#{category_id("Delivery")}]"))

    delivery = db[:savings_plan_lines].where(category_id: category_id("Delivery")).first
    expect(delivery).to include(baseline_cents: 2_407) # (45,90 + 47,80 - 21,50) / 3, with the card's iFood refund netted

    post "/plan/#{plan[:id]}/accept", proposed: {category_id("Delivery").to_s => "10.00"}
    expect(last_response.headers["Location"]).to end_with("/budgets")
    expect(db[:savings_plans].where(id: plan[:id]).get(:status)).to eq("active")
    expect(db[:budgets].where(category_id: category_id("Delivery")).first).to include(month: "2026-09", amount_cents: 1_000)
    expect(db[:budgets].count).to eq(db[:savings_plan_lines].count)

    post "/plan/#{plan[:id]}/accept"
    expect(last_response.status).to eq(422)
  end

  it "replaces the active plan with the next one accepted" do
    2.times do
      post "/plan", target: "1,000.00", starts_month: "2026-09"
      post "/plan/#{db[:savings_plans].max(:id)}/accept"
    end

    expect(db[:savings_plans].order(:id).select_map(:status)).to eq(%w[replaced active])
  end

  it "explains a target it can't plan" do
    post "/plan", target: "abc"
    follow_redirect!
    expect(last_response.body).to include("Enter how much to save each month")

    allow(Date).to receive(:today).and_return(Date.new(2030, 1, 1))
    post "/plan", target: "100.00"
    follow_redirect!
    expect(last_response.body).to include("There are no rows in the last three complete months")
  end

  it "tracks the month against its budgets, and scores it once it's over" do
    db[:transactions].where(raw_description: "Compra no débito via NuPay - iFood").update(occurred_on: "2026-09-10")
    post "/plan", target: "1,000.00", starts_month: "2026-09"
    post "/plan/#{db[:savings_plans].max(:id)}/accept", proposed: {category_id("Delivery").to_s => "10.00"}

    allow(Date).to receive(:today).and_return(Date.new(2026, 9, 15))
    get "/budgets"
    body = last_response.body
    expect(body).to include("50% of Sep 2026 has gone by.", "Target<strong>R$ 1,000.00</strong>")
    expect(body).to match(%r{<td>Alimentação › Delivery</td>\s*<td class="num">R\$ 45.90</td>}m)
    expect(body).to include("918%", ">over<")

    post "/budgets", category_id: category_id("Delivery").to_s, month: "2026-10", amount: "60.00"
    expect(db[:budgets].where(category_id: category_id("Delivery")).order(:month).select_map(%i[month amount_cents]))
      .to eq([["2026-09", 1_000], ["2026-10", 6_000]])

    allow(Date).to receive(:today).and_return(Date.new(2026, 10, 3))
    get "/budgets", month: "2026-09"
    expect(last_response.body).to include("Sep 2026 is over.", "Target missed", "Over budget: Delivery (R$ 35.90)")
    expect(last_response.body).to include("Month-end scores")
  end

  it "says there are no budgets before a plan" do
    get "/budgets"

    expect(last_response.body).to include("No budgets for Aug 2026 yet.")
  end
end
