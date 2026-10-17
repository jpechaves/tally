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
    expect(body).to include("Save R$ 2,500.00 a month", "Transfers (Pix)", %(name="proposed[#{category_id("Delivery")}]"))

    delivery = db[:savings_plan_lines].where(category_id: category_id("Delivery")).first
    expect(delivery).to include(baseline_cents: 2_407) # (45,90 + 47,80 - 21,50) / 3, with the card's iFood refund netted

    post "/plan/#{plan[:id]}/accept", proposed: {category_id("Delivery").to_s => "10.00"}
    expect(last_response.headers["Location"]).to end_with("/budgets?month=2026-09")
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
    expect(body).to match(%r{<td>Food › Food delivery\s*<div class="meter over" title="R\$ 45.90 / R\$ 10.00">\s*<span style="width: 100.0%"></span><i style="left: 50.0%"></i>.*?</td>\s*<td class="num">R\$ 45.90</td>}m)
    expect(body).to include("918%", ">over<")

    post "/budgets", category_id: category_id("Delivery").to_s, month: "2026-10", amount: "60.00"
    expect(db[:budgets].where(category_id: category_id("Delivery")).order(:month).select_map(%i[month amount_cents]))
      .to eq([["2026-09", 1_000], ["2026-10", 6_000]])

    allow(Date).to receive(:today).and_return(Date.new(2026, 10, 3))
    get "/budgets", month: "2026-09"
    expect(last_response.body).to include("Sep 2026 is over.", "Target missed", "Over budget: Food delivery (R$ 35.90)")
    expect(last_response.body).to include("Month-end scores")
  end

  it "shows no target or plan banner for a month before the plan starts" do
    post "/plan", target: "1,000.00", starts_month: "2026-09"
    post "/plan/#{db[:savings_plans].max(:id)}/accept", proposed: {category_id("Delivery").to_s => "10.00"}
    post "/budgets", category_id: category_id("Delivery").to_s, month: "2026-08", amount: "5.00"

    allow(Date).to receive(:today).and_return(Date.new(2026, 8, 15))
    get "/budgets", month: "2026-08"
    body = last_response.body
    expect(body).to include("Your plan to save R$ 1,000.00 a month starts in Sep 2026, so Aug 2026 has no target")
    expect(body).to include("no savings target this month")
    expect(body).not_to include("These limits come from your plan", "on track", "Target<strong>")

    get "/budgets", month: "2026-09"
    expect(last_response.body).to include("These limits come from your plan", "Target<strong>R$ 1,000.00</strong>")
  end

  it "counts a row dated after today as committed, not spent" do
    db[:transactions].where(raw_description: "Compra no débito via NuPay - iFood").update(occurred_on: "2026-09-20")
    post "/plan", target: "1,000.00", starts_month: "2026-09"
    post "/plan/#{db[:savings_plans].max(:id)}/accept", proposed: {category_id("Delivery").to_s => "10.00"}

    allow(Date).to receive(:today).and_return(Date.new(2026, 9, 15))
    get "/budgets"
    body = last_response.body
    expect(body).to match(%r{<td class="num">R\$ 0.00\s*<span class="note">\+ R\$ 45.90 to come</span></td>}m)
    expect(body).to include("R$ 45.90 on bills already imported is dated later this month")
    expect(body).not_to include(">over<")

    get "/transactions", month: "2026-09"
    expect(last_response.body).to include("not charged yet")
    get "/report", month: "2026-09"
    expect(last_response.body).not_to include(">Food delivery</a>")

    allow(Date).to receive(:today).and_return(Date.new(2026, 9, 20))
    get "/budgets"
    expect(last_response.body).to include(">over<")
    expect(last_response.body).not_to include("to come")
    get "/report", month: "2026-09"
    expect(last_response.body).to include(">Food delivery</a>")
  end

  it "runs the plan's live recalculation and confirmations from script files the Content Security Policy allows" do
    post "/plan", target: "1,000.00", starts_month: "2026-09"
    follow_redirect!

    expect(last_response.headers["Content-Security-Policy"]).to include("script-src 'self'")
    expect(last_response.body).to include(%(<script src="/assets/plan.js"></script>), %(data-target="100000"), %(data-decimal="."), %(data-reaches="reaches the target"))
    expect(last_response.body.scan(/<script[^>]*>/)).to eq([%(<script src="/assets/confirm.js" defer>), %(<script src="/assets/plan.js">)])

    get "/assets/plan.js"
    expect(last_response.status).to eq(200)
    expect(last_response.headers["Content-Type"]).to start_with("text/javascript")
    expect(last_response.body).to include("new-saved", "confirmShort")

    get "/assets/confirm.js"
    expect(last_response.headers["Content-Type"]).to start_with("text/javascript")
    expect(last_response.body).to include("dataset.confirm")

    get "/assets/other.js"
    expect(last_response.status).to eq(404)
  end

  it "warns when the accepted limits save less than the target" do
    post "/plan", target: "1,000,000.00", starts_month: "2026-09"
    post "/plan/#{db[:savings_plans].max(:id)}/accept"
    follow_redirect!

    expect(last_response.body).to match(/short of its R\$ 1,000,000\.00 target/)
  end

  it "shows the plan's target only from the month the plan starts" do
    post "/plan", target: "1,000.00", starts_month: "2026-09"
    post "/plan/#{db[:savings_plans].max(:id)}/accept"
    post "/budgets", category_id: category_id("Delivery").to_s, month: "2026-08", amount: "10.00"

    get "/budgets", month: "2026-08"
    expect(last_response.body).to include("Projected")
    expect(last_response.body).not_to include("Target<strong>")

    get "/budgets", month: "2026-09"
    expect(last_response.body).to include("Target<strong>R$ 1,000.00</strong>")
  end

  it "sends an invalid limit back to the page with an error" do
    post "/budgets", category_id: category_id("Delivery").to_s, month: "2026-09", amount: "abc"
    expect(last_response.headers["Location"]).to end_with("/budgets?month=2026-09&error=invalid_limit")
    follow_redirect!
    expect(last_response.body).to include("A limit is an amount of zero or more")

    post "/budgets", category_id: "999999", month: "2026-09", amount: "10.00"
    follow_redirect!
    expect(last_response.body).to include("Pick a month and a spending category.")
  end

  it "projects next month from complete months only, not the partly imported current one" do
    post "/budgets", category_id: category_id("Delivery").to_s, month: "2026-09", amount: "10.00"
    projected = -> { get("/budgets", month: "2026-09") && last_response.body[%r{Projected<strong[^>]*>(.*?)</strong>}, 1] }
    before = projected.()

    row = db[:transactions].where(raw_description: "Compra no débito via NuPay - iFood").first
    db[:transactions].insert(row.except(:id).merge(occurred_on: "2026-08-10", amount_cents: -500_000,
      raw_description: "Loja exemplo", description: "Loja exemplo", category_id: nil, external_id: "partial-month"))

    expect(projected.()).to eq(before)
  end

  it "says there are no budgets before a plan" do
    get "/budgets"

    expect(last_response.body).to include("No budgets for Aug 2026 yet.")
  end

  describe "deleting" do
    def accept(target = "1,000.00", proposed: {})
      post "/plan", target:, starts_month: "2026-09"
      id = db[:savings_plans].max(:id)
      post "/plan/#{id}/accept", proposed.empty? ? {} : {proposed:}
      id
    end

    def limits(month) = Hanami.app["repos.plan_repo"].budgets_for(month)

    it "deletes a draft plan and its lines" do
      post "/plan", target: "1,000.00", starts_month: "2026-09"
      id = db[:savings_plans].max(:id)
      get "/plan/#{id}"
      expect(last_response.body).to include("Delete this plan", %(data-confirm="Delete this plan? This can&#39;t be undone."))
      expect(last_response.body).not_to include("remove_budgets")

      post "/plan/#{id}/delete"
      expect(last_response.headers["Location"]).to end_with("/plan?notice=plan_deleted")
      expect(db[:savings_plans].count).to eq(0)
      expect(db[:savings_plan_lines].count).to eq(0)
      follow_redirect!
      expect(last_response.body).to include("The plan was deleted.")

      post "/plan/#{id}/delete"
      expect(last_response.status).to eq(404)
    end

    it "removes the budgets an accepted plan wrote, back to the limits from before, and nothing else" do
      post "/budgets", category_id: category_id("Delivery").to_s, month: "2026-08", amount: "30.00"
      counts = -> { [db[:transactions].count, db[:categories].count, db[:category_rules].count] }
      before = counts.()
      id = accept(proposed: {category_id("Delivery").to_s => "10.00"})
      expect(limits("2026-09")[category_id("Delivery")]).to eq(1_000)

      get "/plan/#{id}"
      written = db[:budgets].where(savings_plan_id: id).count
      expect(last_response.body).to include(%(name="remove_budgets" value="1" checked), "Also remove the #{written} budgets it wrote")

      post "/plan/#{id}/delete", remove_budgets: "1"
      expect(last_response.headers["Location"]).to end_with("notice=plan_deleted_with_budgets")
      expect(db[:savings_plans].count).to eq(0)
      expect(limits("2026-09")).to eq(category_id("Delivery") => 3_000)
      expect(counts.()).to eq(before)
    end

    it "keeps the budgets when asked, as if set by hand" do
      id = accept
      written = db[:budgets].count

      post "/plan/#{id}/delete"
      expect(last_response.headers["Location"]).to end_with("notice=plan_deleted_kept_budgets")
      expect(db[:budgets].count).to eq(written)
      expect(db[:budgets].exclude(savings_plan_id: nil).count).to eq(0)

      get "/budgets", month: "2026-09"
      expect(last_response.body).not_to include("Target<strong>")
    end

    it "removes one category's budget from a month on, keeping the months before" do
      delivery = category_id("Delivery").to_s
      post "/budgets", category_id: delivery, month: "2026-08", amount: "10.00"
      post "/budgets", category_id: delivery, month: "2026-10", amount: "60.00"

      get "/budgets", month: "2026-09"
      expect(last_response.body).to include(%(action="/budgets/remove"), %(data-confirm="Remove the Food delivery budget from Sep 2026 on?"))

      post "/budgets/remove", category_id: delivery, month: "2026-09"
      expect(last_response.headers["Location"]).to end_with("/budgets?month=2026-09")
      expect([limits("2026-08"), limits("2026-09"), limits("2026-11")]).to eq([{delivery.to_i => 1_000}, {}, {}])

      post "/budgets", category_id: delivery, month: "2026-11", amount: "20.00"
      expect([limits("2026-10"), limits("2026-11")]).to eq([{}, {delivery.to_i => 2_000}])

      post "/budgets/remove", category_id: "999999", month: "2026-09"
      expect(last_response.headers["Location"]).to end_with("error=month_and_category")
    end

    it "removes every budget from a month on" do
      accept
      post "/budgets", category_id: category_id("Delivery").to_s, month: "2026-08", amount: "10.00"

      get "/budgets", month: "2026-09"
      expect(last_response.body).to include("Remove all budgets from Sep 2026 on")

      post "/budgets/remove", all: "1", month: "2026-09"
      expect(limits("2026-09")).to eq({})
      expect(limits("2026-08")).to eq(category_id("Delivery") => 1_000)
      get "/budgets", month: "2026-09"
      expect(last_response.body).to include("No budgets for Sep 2026 yet.")
    end
  end

  describe "the way from a plan to budgets" do
    def current_step = last_response.body[%r{<li aria-current="step">\s*<strong>(.*?)</strong>}m, 1]

    it "walks a first-time user through each step, saying what each one changes" do
      get "/plan"
      body = last_response.body
      expect(body).to include("<h1>Savings plan</h1>", %(<a href="/plan" aria-current="page">Savings plan</a>))
      expect(body).to include("A savings plan is a proposal", %(<details class="flow" open>))
      expect(current_step).to eq("1. Make a plan.")

      get "/budgets"
      expect(last_response.body).to include("A budget is a monthly limit for one category.")
      expect(current_step).to eq("1. Make a plan.")

      post "/plan", target: "1,000.00", starts_month: "2026-09"
      id = db[:savings_plans].max(:id)
      get "/plan/#{id}"
      expect(last_response.body).to include("This is a draft: nothing has changed yet.")
      get "/plan"
      expect(last_response.body).to include("A draft to save R$ 1,000.00 a month is waiting", %(<a href="/plan/#{id}">Review and accept</a>))
      expect(current_step).to eq("2. Accept it.")

      post "/plan/#{id}/accept"
      count = db[:budgets].where(savings_plan_id: id).count
      get "/plan"
      body = last_response.body
      expect(body).to include(%(<details class="flow">), "<td>Accepted</td>", %(<a href="/budgets?month=2026-09">#{count} budgets from Sep 2026</a>))
      expect(current_step).to eq("3. Follow your budgets.")

      get "/plan/#{id}"
      expect(last_response.body).to include("Accepted: its #{count} limits are your budgets from Sep 2026.", %(<a href="/budgets?month=2026-09">See them on Budgets</a>))

      get "/budgets", month: "2026-09"
      expect(last_response.body).to include("These limits come from your plan to save R$ 1,000.00 a month, accepted from Sep 2026.", %(<a href="/plan/#{id}">See the plan</a>))

      post "/plan", target: "500.00", starts_month: "2026-09"
      post "/plan/#{db[:savings_plans].max(:id)}/accept"
      get "/plan/#{id}"
      expect(last_response.body).to include("A newer plan replaced this one.")
    end

    it "uses the same words in Portuguese" do
      set_cookie "locale=pt-BR"
      post "/plan", target: "1.000,00", starts_month: "2026-09"
      post "/plan/#{db[:savings_plans].max(:id)}/accept"

      get "/plan"
      body = last_response.body
      expect(body).to include("<h1>Plano de economia</h1>", %(aria-current="page">Plano de economia</a>), "<td>Aceito</td>", "orçamentos a partir de set/2026")
      expect(current_step).to eq("3. Acompanhe seus orçamentos.")
    end
  end
end
