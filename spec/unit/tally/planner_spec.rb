# frozen_string_literal: true

RSpec.describe Tally::Planner do
  let(:months) { %w[2026-06 2026-07 2026-08] }

  # Every month: income 12.000, discretionary 5.000, essential 4.000, fixed 1.500 (the
  # worked example in docs/architecture.md, 8.4).
  let(:rows) do
    months.flat_map do |month|
      [
        insight_row("#{month}-05", 12_000.00, "EMPRESA EXEMPLO"),
        insight_row("#{month}-10", -3_000.00, "IFOOD", **in_category(:delivery)),
        insight_row("#{month}-11", -2_000.00, "ACADEMIA", **in_category(:gym)),
        insight_row("#{month}-12", -4_000.00, "MERCADO", **in_category(:market)),
        insight_row("#{month}-15", -1_500.00, "ENERGIA", **in_category(:energy)),
        insight_row("#{month}-20", -800.00, "Pagamento de fatura", kind: "transfer")
      ]
    end
  end

  def plan(target, rows: self.rows) = described_class.new(rows, months:, target_cents: (target * 100).round)

  it "splits the gap over what each category may be cut, adding up exactly" do
    planner = plan(3_000.00)

    expect(planner).to have_attributes(income_cents: 1_200_000, spending_cents: 1_050_000, saved_today_cents: 150_000,
      gap_cents: 150_000, cuttable_cents: 310_000, shortfall_cents: 0, cuts_cents: 150_000)
    expect(planner.lines.map { [_1.name, _1.baseline_cents, _1.max_cut_cents, _1.cut_cents, _1.proposed_cents] }).to eq([
      ["Supermercado", 400_000, 60_000, 29_032, 370_968],
      ["Delivery", 300_000, 150_000, 72_581, 227_419],
      ["Academia", 200_000, 100_000, 48_387, 151_613],
      ["Energia", 150_000, 0, 0, 150_000]
    ])
    # Discretionary gives up 1.209,68 and essential 290,32, as in the docs.
    expect(planner.lines.select { _1.nature == "discretionary" }.sum(&:cut_cents)).to eq(120_968)
  end

  it "cuts everything it may and reports the shortfall when that isn't enough" do
    planner = plan(5_000.00)

    expect(planner).to have_attributes(gap_cents: 350_000, cuts_cents: 310_000, shortfall_cents: 40_000)
    expect(planner.lines.map(&:cut_cents)).to eq(planner.lines.map(&:max_cut_cents))
    expect(planner.fixed_lines.map(&:name)).to eq(["Energia"])
  end

  it "proposes no cuts when you already save the target" do
    planner = plan(1_000.00)

    expect(planner).to be_already_there
    expect(planner).to have_attributes(cuts_cents: 0, shortfall_cents: 0)
    expect(planner.lines.map(&:proposed_cents)).to eq(planner.lines.map(&:baseline_cents))
  end

  it "averages over all the baseline months, nets refunds, and counts rows with no category" do
    rows = [
      insight_row("2026-08-10", -300.00, "IFOOD", **in_category(:delivery)),
      insight_row("2026-08-11", 30.00, "IFOOD", kind: "refund", **in_category(:delivery)),
      insight_row("2026-08-12", -90.00, "LOJA")
    ]
    planner = plan(100.00, rows:)

    expect(planner.lines.map { [_1.name, _1.baseline_cents] }).to eq([["Delivery", 9_000]])
    expect(planner).to have_attributes(spending_cents: 12_000, uncategorized_cents: 3_000)
  end

  it "refuses a target that isn't positive" do
    expect { plan(0) }.to raise_error(ArgumentError)
  end
end
