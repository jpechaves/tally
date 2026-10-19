# frozen_string_literal: true

RSpec.describe Tally::InstallmentCalendar do
  let(:rows) do
    [
      insight_row("2026-08-02", -120.00, "LOJA EXEMPLO", installment_number: 2, installment_total: 4, purchase_key: "a"),
      insight_row("2026-09-02", -120.00, "LOJA EXEMPLO", installment_number: 3, installment_total: 4, purchase_key: "a"),
      insight_row("2026-09-02", -1_504.14, "VOO EXEMPLO", installment_number: 8, installment_total: 10, purchase_key: "b"),
      insight_row("2026-09-02", -50.00, "ULTIMA", installment_number: 2, installment_total: 2, purchase_key: "c"),
      insight_row("2026-05-02", -30.00, "ANTIGA", installment_number: 1, installment_total: 3, purchase_key: "d")
    ]
  end

  it "projects each purchase's remaining installments from its latest one" do
    calendar = described_class.new(rows, from: "2026-10")

    expect(calendar.purchases.map { [_1.description, _1.number, _1.total, _1.ends] })
      .to eq([["LOJA EXEMPLO", 3, 4, "2026-10"], ["VOO EXEMPLO", 8, 10, "2026-11"]])
    expect(calendar.months).to eq("2026-10" => 162_414, "2026-11" => 150_414)
    expect(calendar.total_cents).to eq(312_828)
  end

  it "links a purchase's installments even when the first one carries the rounding cents" do
    rows = [
      insight_row("2026-08-02", -100.03, "TV EXEMPLO", installment_number: 1, installment_total: 3, purchase_key: "x1"),
      insight_row("2026-09-02", -100.00, "TV EXEMPLO", installment_number: 2, installment_total: 3, purchase_key: "x2"),
      # The same merchant and count, started a month later: another purchase.
      insight_row("2026-09-02", -40.00, "TV EXEMPLO", installment_number: 1, installment_total: 3, purchase_key: "y1"),
      # Two identical purchases the same month stay two.
      insight_row("2026-09-02", -25.00, "LIVRO", installment_number: 1, installment_total: 2, purchase_key: "z"),
      insight_row("2026-09-02", -25.00, "LIVRO", installment_number: 1, installment_total: 2, purchase_key: "z")
    ]
    calendar = described_class.new(rows, from: "2026-10")

    expect(calendar.purchases.map { [_1.description, _1.number, _1.cents] })
      .to contain_exactly(["TV EXEMPLO", 2, 10_000], ["TV EXEMPLO", 1, 4_000], ["LIVRO", 1, 2_500], ["LIVRO", 1, 2_500])
    expect(calendar.months).to eq("2026-10" => 19_000, "2026-11" => 4_000)
  end

  it "names the first month with something committed, after `from` when that month has none" do
    expect(described_class.new(rows, from: "2026-09").first_month).to eq("2026-10")
    expect(described_class.new(rows, from: "2026-11").first_month).to eq("2026-11")
    expect(described_class.new(rows, from: "2027-06").first_month).to eq("2027-06")
  end

  it "counts only the months from `from` on" do
    calendar = described_class.new(rows, from: "2026-11")

    expect(calendar.months).to eq("2026-11" => 150_414)
    expect(calendar.purchases.map { [_1.description, _1.left_from("2026-11")] }).to eq([["VOO EXEMPLO", 1]])
  end

  it "treats installments paid in advance as the same purchase, finished at n/n" do
    rows = [
      insight_row("2026-07-02", -80.00, "CURSO EXEMPLO", installment_number: 3, installment_total: 10, bill_due_on: "2026-07-09"),
      insight_row("2026-08-02", -80.00, "CURSO EXEMPLO", installment_number: 4, installment_total: 10, bill_due_on: "2026-08-09"),
      *(5..10).map do |number|
        insight_row("2026-08-03", -78.00, "CURSO EXEMPLO", installment_number: number, installment_total: 10, bill_due_on: "2026-08-09")
      end,
      # Paid early on one bill, with installments left after it.
      insight_row("2026-08-02", -30.00, "FONE EXEMPLO", installment_number: 2, installment_total: 6, bill_due_on: "2026-08-09"),
      insight_row("2026-08-03", -30.00, "FONE EXEMPLO", installment_number: 3, installment_total: 6, bill_due_on: "2026-08-09")
    ]
    calendar = described_class.new(rows, from: "2026-09")

    expect(calendar.purchases.map { [_1.description, _1.number, _1.ends] }).to eq([["FONE EXEMPLO", 3, "2026-11"]])
  end

  it "links installments by bill when they post on either side of a month's start" do
    rows = [
      insight_row("2026-07-31", -45.00, "MALA EXEMPLO", installment_number: 1, installment_total: 4, bill_due_on: "2026-08-09"),
      insight_row("2026-09-01", -45.00, "MALA EXEMPLO", installment_number: 2, installment_total: 4, bill_due_on: "2026-09-09")
    ]
    calendar = described_class.new(rows, from: "2026-10")

    expect(calendar.purchases.map { [_1.number, _1.ends] }).to eq([[2, "2026-11"]])
  end

  it "keeps a purchase seen only mid-way apart from an older one it can't follow" do
    rows = [
      insight_row("2026-01-02", -60.00, "SOFA EXEMPLO", installment_number: 1, installment_total: 3, bill_due_on: "2026-01-09"),
      insight_row("2026-09-02", -60.00, "SOFA EXEMPLO", installment_number: 2, installment_total: 3, bill_due_on: "2026-09-09")
    ]
    calendar = described_class.new(rows, from: "2026-10")

    expect(calendar.purchases.map { [_1.number, _1.ends] }).to eq([[2, "2026-10"]])
  end

  it "finds the purchase an installment belongs to, and what is left of it" do
    rows = [
      insight_row("2026-08-02", -100.03, "TV EXEMPLO", installment_number: 1, installment_total: 3),
      insight_row("2026-09-02", -100.00, "TV EXEMPLO", installment_number: 2, installment_total: 3),
      insight_row("2026-09-02", -40.00, "TV EXEMPLO", installment_number: 1, installment_total: 3)
    ]
    series = described_class.series_of(rows, rows.first[:id])
    expect(series).to eq(rows.first(2))
    expect(described_class.series_of(rows, 999)).to eq([])

    purchase = described_class::Purchase.of(series)
    expect(purchase).to have_attributes(id: rows[1][:id], number: 2, left: 1, ends: "2026-10")
    expect([purchase.left_from("2026-10"), purchase.left_cents_from("2026-10")]).to eq([1, 10_000])
    expect(purchase.left_cents_from("2026-11")).to eq(0)
  end
end
