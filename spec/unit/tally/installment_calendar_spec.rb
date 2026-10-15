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

  it "counts only the months from `from` on" do
    calendar = described_class.new(rows, from: "2026-11")

    expect(calendar.months).to eq("2026-11" => 150_414)
    expect(calendar.purchases.map { [_1.description, _1.left_from("2026-11")] }).to eq([["VOO EXEMPLO", 1]])
  end
end
