# frozen_string_literal: true

RSpec.describe Tally::Report do
  let(:rows) do
    [
      # Baseline: June, July, August.
      *%w[2026-06 2026-07 2026-08].flat_map do |month|
        [
          insight_row("#{month}-05", 9_000.00, "EMPRESA EXEMPLO LTDA"),
          insight_row("#{month}-10", -200.00, "IFOOD", **in_category(:delivery)),
          insight_row("#{month}-12", -800.00, "MERCADO EXEMPLO", **in_category(:market)),
          insight_row("#{month}-15", -300.00, "ENERGIA EXEMPLO", **in_category(:energy))
        ]
      end,
      # September.
      insight_row("2026-09-05", 9_000.00, "EMPRESA EXEMPLO LTDA"),
      insight_row("2026-09-08", -400.00, "IFOOD", **in_category(:delivery)),
      insight_row("2026-09-09", 50.00, "IFOOD", kind: "refund", **in_category(:delivery)),
      insight_row("2026-09-12", -800.00, "MERCADO EXEMPLO", **in_category(:market)),
      insight_row("2026-09-15", -300.00, "ENERGIA EXEMPLO", **in_category(:energy)),
      insight_row("2026-09-20", -150.00, "LOJA EXEMPLO", installment_number: 3, installment_total: 10, purchase_key: "a"),
      insight_row("2026-09-21", -99.99, "LOJA DOIS", installment_number: 2, installment_total: 2, purchase_key: "b")
    ]
  end
  let(:report) { described_class.new(rows, month: "2026-09") }

  it "adds up income, spending and saved, next to the 3-month average" do
    expect(report.averaged_months).to eq(%w[2026-06 2026-07 2026-08])
    expect(report).to have_attributes(
      income_cents: 900_000, spending_cents: 169_999, saved_cents: 730_001,
      average_income_cents: 900_000, average_spending_cents: 130_000, average_saved_cents: 770_000
    )
  end

  it "breaks spending down by parent and category, biggest first, refunds netted" do
    food = report.categories.first

    expect(food).to have_attributes(name: "Alimentação", cents: 115_000, average_cents: 100_000, change: 15.0, rows: 3)
    expect(food.children.map { [_1.name, _1.cents, _1.average_cents, _1.change] })
      .to eq([["Supermercado", 80_000, 80_000, 0.0], ["Delivery", 35_000, 20_000, 75.0]])
    expect(report.categories.map(&:name)).to eq(["Alimentação", "Moradia", nil])
    expect(report.categories.sum(&:cents)).to eq(report.spending_cents)
  end

  it "splits spending by nature" do
    expect(report.natures.map { [_1.name, _1.cents] })
      .to eq([["essential", 80_000], ["discretionary", 35_000], ["fixed", 30_000], ["unset", 24_999]])
  end

  it "lists top payees" do
    expect(report.payees(limit: 2).map { [_1.name, _1.cents, _1.rows] })
      .to eq([["MERCADO EXEMPLO", 80_000, 1], ["IFOOD", 35_000, 2]])
  end

  it "shows the month's installments and when each ends" do
    expect(report.installments.map { [_1[:row][:description], _1[:cents], _1[:ends]] })
      .to eq([["LOJA EXEMPLO", 15_000, "2027-04"], ["LOJA DOIS", 9_999, "2026-09"]])
    expect(report.installments_cents).to eq(24_999)
  end

  it "averages over the earlier months it has, and none without them" do
    report = described_class.new(rows.reject { _1[:occurred_on] < "2026-08" }, month: "2026-09")
    expect(report.averaged_months).to eq(%w[2026-08])

    first = described_class.new(rows.select { _1[:occurred_on] >= "2026-09" }, month: "2026-09")
    expect(first).to have_attributes(average_spending_cents: 0, averaged_months: [])
    expect(first.categories.first.change).to be_nil
  end
end
