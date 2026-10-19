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

  it "counts rows dated after today as committed, not spent, until their date" do
    upcoming = rows + [
      insight_row("2026-09-25", -300.00, "LOJA EXEMPLO - Parcela 3/5", **in_category(:market)),
      insight_row("2026-09-28", -80.00, "LOJA")
    ]
    early = described_class.new(upcoming, month: "2026-09", budgets: {11 => 500_00, 12 => 2_000_00}, categories:,
      today: Date.new(2026, 9, 12), expected_income_cents: 10_000_00, expected_unbudgeted_cents: 50_00)

    market = early.lines.find { _1.name == "Supermercado" }
    expect(early.spending_cents).to eq(110_000)
    expect(early.saved_cents).to eq(890_000)
    expect(market).to have_attributes(spent_cents: 60_000, committed_cents: 30_000, pace_pct: 75)
    expect(early.committed_cents).to eq(38_000)
    # Committed R$ 80 outside the budgets is more than the usual R$ 50 still to come.
    expect(early.unbudgeted_left_cents).to eq(8_000)

    late = described_class.new(upcoming, month: "2026-09", budgets: {11 => 500_00, 12 => 2_000_00}, categories:,
      today: Date.new(2026, 9, 25), expected_income_cents: 10_000_00)
    expect(late.lines.find { _1.name == "Supermercado" }).to have_attributes(spent_cents: 90_000, committed_cents: 0)
    expect(late.committed_cents).to eq(8_000)
  end

  it "projects committed spending over what's left of a budget" do
    big = rows + [insight_row("2026-09-20", -700.00, "IFOOD", **in_category(:delivery))]
    september = described_class.new(big, month: "2026-09", budgets: {11 => 500_00, 12 => 2_000_00}, categories:,
      today: Date.new(2026, 9, 15), expected_income_cents: 10_000_00)

    # Delivery: R$ 100 left, but R$ 700 already committed.
    expect(september.projected_saved_cents).to eq(1_000_000 - 110_000 - 140_000 - 70_000)
  end

  it "is never on track without a target" do
    expect(month(Date.new(2026, 9, 15), target: nil)).not_to be_on_track
    expect(month(Date.new(2026, 10, 2), target: nil).score).to be_nil
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

  it "has no pace for spending in a budget of zero, and is on pace with nothing spent" do
    zero = described_class.new(rows, month: "2026-09", budgets: {11 => 0, 12 => 0}, categories:, today: Date.new(2026, 9, 15))
    unspent = described_class.new([], month: "2026-09", budgets: {11 => 0}, categories:, today: Date.new(2026, 9, 15))

    expect(zero.lines.map { [_1.name, _1.pace_pct, _1.over?] }).to eq([["Delivery", nil, true], ["Supermercado", nil, true]])
    expect(unspent.lines.first).to have_attributes(pace_pct: 0, ahead_of_pace?: false, over?: false)
  end

  it "expects nothing more outside the budgets once the month is over" do
    september = described_class.new(rows, month: "2026-09", budgets: {11 => 500_00, 12 => 2_000_00}, categories:,
      today: Date.new(2026, 10, 2), expected_income_cents: 10_000_00, expected_unbudgeted_cents: 3_000_00)

    expect(september.unbudgeted_left_cents).to eq(0)
  end

  it "names a budget whose category it doesn't know by its id" do
    september = described_class.new(rows, month: "2026-09", budgets: {99 => 100_00}, categories:, today: Date.new(2026, 9, 15))

    expect(september.lines.first).to have_attributes(name: "#99", parent_name: nil)
  end
end
