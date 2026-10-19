# frozen_string_literal: true

RSpec.describe Tally::Repos::PlanRepo, :db do
  subject(:repo) { Hanami.app["repos.plan_repo"] }

  let(:db) { Hanami.app["db.gateway"].connection }
  let(:category) { db[:categories].insert(name: "Feira", kind: "expense") }

  def budget_rows = db[:budgets].where(category_id: category).order(:month).select_map([:month, :amount_cents, :removed])

  it "ends a budget with one removed row, and only when a budget was running before" do
    repo.remove_budget(category, "2026-08")
    expect(budget_rows).to eq([])

    repo.set_budget(category, "2026-07", 50_000)
    repo.remove_budget(category, "2026-08")
    repo.remove_budget(category, "2026-09")
    expect(budget_rows).to eq([["2026-07", 50_000, 0], ["2026-08", 0, 1]])
    expect(repo.budgets_for("2026-07")).to eq(category => 50_000)
    expect(repo.budgets_for("2026-09")).to eq({})
  end

  it "counts no budgets for a plan that wrote none" do
    plan = db[:savings_plans].insert(target_cents: 100_000, starts_month: "2026-09", baseline_from: "2026-06",
      baseline_to: "2026-08", baseline_income_cents: 0, baseline_spending_cents: 0)

    expect(repo.budget_count(plan)).to eq(0)
    expect(repo.find(plan)).to include(id: plan, status: "draft")
  end
end
