# frozen_string_literal: true

RSpec.describe Tally::Insights do
  it "counts refunds as negative spending, and leaves transfers out of both sides" do
    rows = [
      insight_row("2026-09-01", -100.00, "LOJA", kind: "purchase"),
      insight_row("2026-09-02", 30.00, "LOJA", kind: "refund"),
      insight_row("2026-09-03", -5.00, "TARIFA", kind: "fee"),
      insight_row("2026-09-04", -40.00, "BOLETO", kind: "bill_payment"),
      insight_row("2026-09-05", -1_000.00, "Pagamento de fatura", kind: "transfer"),
      insight_row("2026-09-06", 2_000.00, "EMPRESA", kind: "income")
    ]

    expect(described_class.spent_cents(rows)).to eq(11_500)
    expect(described_class.income_cents(rows)).to eq(200_000)
  end

  it "adds up each month, with zeros for a month without rows" do
    rows = [insight_row("2026-08-01", -10.00, "LOJA"), insight_row("2026-09-01", 20.00, "EMPRESA")]

    expect(described_class.monthly(rows, %w[2026-07 2026-08 2026-09])).to eq([
      {month: "2026-07", income_cents: 0, spending_cents: 0},
      {month: "2026-08", income_cents: 0, spending_cents: 1_000},
      {month: "2026-09", income_cents: 2_000, spending_cents: 0}
    ])
  end

  it "counts months across years" do
    expect(described_class.previous_months("2026-02", 3)).to eq(%w[2025-11 2025-12 2026-01])
    expect(described_class.next_months("2026-11", 3)).to eq(%w[2026-12 2027-01 2027-02])
    expect(described_class.months_between("2025-11", "2026-02")).to eq(3)
    expect(described_class.months_between("2026-02", "2025-11")).to eq(-3)
  end

  it "opens on the latest month that is over, or the latest one" do
    today = Date.new(2026, 9, 15)

    expect(described_class.default_month(%w[2026-07 2026-08 2026-09], today:)).to eq("2026-08")
    expect(described_class.default_month(%w[2026-09], today:)).to eq("2026-09")
    expect(described_class.default_month([], today:)).to be_nil
  end

  it "averages whole cents, rounding half away from zero, and nothing to zero" do
    expect(described_class.average([1, 2])).to eq(2)
    expect(described_class.average([-1, -2])).to eq(-2)
    expect(described_class.average([1, 1, 2])).to eq(1)
    expect(described_class.average([])).to eq(0)
  end

  it "gives a share with one decimal, and none of nothing" do
    expect(described_class.share(1, 3)).to eq(33.3)
    expect(described_class.share(5, 0)).to eq(0)
  end

  it "labels a payee by its counterparty, or the description" do
    expect(described_class.payee_label(insight_row("2026-09-01", -1.00, "PIX", counterparty_name: "Maria"))).to eq("Maria")
    expect(described_class.payee_label(insight_row("2026-09-01", -1.00, "PIX"))).to eq("PIX")
  end
end
