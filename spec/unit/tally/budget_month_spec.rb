# frozen_string_literal: true

RSpec.describe Tally::BudgetMonth do
  let(:categories) { {11 => {name: "Delivery", parent_name: "Alimentação"}, 12 => {name: "Supermercado", parent_name: "Alimentação"}} }
  let(:rows) do
    [
      insight_row("2026-09-05", 10_000.00, "EMPRESA EXEMPLO"),
      insight_row("2026-09-08", -400.00, "IFOOD", **in_category(:delivery)),
      insight_row("2026-09-09", -600.00, "MERCADO", **in_category(:market)),
      insight_row("2026-09-10", -100.00, "LOJA"),
      insight_row("2026-08-30", -999.00, "IFOOD", **in_category(:delivery))
    ]
  end

  def month(today, target: 3_000_00, income: 10_000_00)
    described_class.new(rows, month: "2026-09", budgets: {11 => 500_00, 12 => 2_000_00}, categories:,
      today:, target_cents: target, expected_income_cents: income)
  end

  it "shows each budget's spending, what's left and its pace" do
    september = month(Date.new(2026, 9, 15))

    expect(september.elapsed).to eq(Rational(1, 2))
    expect(september.lines.map { [_1.name, _1.spent_cents, _1.left_cents, _1.pace_pct, _1.ahead_of_pace?] }).to eq([
      ["Supermercado", 60_000, 140_000, 60, false],
      ["Delivery", 40_000, 10_000, 160, true]
    ])
    expect(september.unbudgeted_cents).to eq(10_000)
  end

  it "projects the month: expected income, minus spending so far and what's left in each budget" do
    september = month(Date.new(2026, 9, 15))

    expect(september.saved_cents).to eq(890_000)
    expect(september.projected_saved_cents).to eq(1_000_000 - 110_000 - 150_000)
    expect(september).to be_on_track
    expect(month(Date.new(2026, 9, 15), target: 8_000_00)).not_to be_on_track
    expect(september.score).to be_nil
  end

  it "expects the usual spending outside the budgets for the rest of the month" do
    september = described_class.new(rows, month: "2026-09", budgets: {11 => 500_00, 12 => 2_000_00}, categories:,
      today: Date.new(2026, 9, 15), expected_income_cents: 10_000_00, expected_unbudgeted_cents: 3_000_00)

    # R$ 100 spent outside the budgets so far, R$ 3.000 usual: R$ 2.900 still to come
    expect(september.unbudgeted_left_cents).to eq(290_000)
    expect(september.projected_saved_cents).to eq(1_000_000 - 110_000 - 150_000 - 290_000)

    over = described_class.new(rows, month: "2026-09", budgets: {11 => 500_00, 12 => 2_000_00}, categories:,
      today: Date.new(2026, 9, 15), expected_income_cents: 10_000_00, expected_unbudgeted_cents: 50_00)
    expect(over.unbudgeted_left_cents).to eq(0)
  end

  it "scores the month once it is over" do
    september = month(Date.new(2026, 10, 2), target: 9_000_00)

    expect(september).to be_complete
    expect(september.score).to include(saved_cents: 890_000, hit: false, difference_cents: -10_000)
    expect(month(Date.new(2026, 10, 2), target: 8_000_00).score).to include(hit: true)

    rows << insight_row("2026-09-28", -200.00, "IFOOD", **in_category(:delivery))
    expect(month(Date.new(2026, 10, 2)).score[:over].map(&:name)).to eq(["Delivery"])
  end

  it "knows a month that hasn't started" do
    expect(month(Date.new(2026, 8, 20))).to have_attributes(elapsed: 0, complete?: false)
  end
end
