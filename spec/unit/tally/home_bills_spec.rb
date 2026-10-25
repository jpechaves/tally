# frozen_string_literal: true

RSpec.describe Tally::HomeBills do
  let(:bill) { {due_day: 10, payee_key: nil, category_id: nil, expected_cents: 18_240} }

  def row(occurred_on, amount, description = "ENERGIA EXEMPLO", **attributes) = insight_row(occurred_on, amount, description, **attributes)

  it "clamps the due day to the month's last day" do
    expect(described_class.due_on("2026-10", 10)).to eq("2026-10-10")
    expect(described_class.due_on("2026-02", 31)).to eq("2026-02-28")
  end

  it "looks at the month before and this month, or the span chosen" do
    today = Date.new(2026, 1, 5)
    expect(described_class.months(today)).to eq(%w[2025-12 2026-01])
    expect(described_class.months(today, "1")).to eq(%w[2026-01])
    expect(described_class.months(today, "6")).to eq(%w[2025-08 2025-09 2025-10 2025-11 2025-12 2026-01])
    expect(described_class.months(today, "all", first: "2025-11")).to eq(%w[2025-11 2025-12 2026-01])
    expect(described_class.months(today, "all", first: "2026-03")).to eq(%w[2026-01])
    expect(described_class.months(today, "all")).to eq(%w[2026-01])
  end

  it "takes a known span or the default, and keeps it in a bill's link" do
    expect(%w[1 6 all].map { described_class.span(_1) }).to eq(%w[1 6 all])
    expect([nil, "3", "x"].map { described_class.span(_1) }).to eq(%w[2 2 2])
    expect(described_class.path(4)).to eq("/home-bills/4")
    expect(described_class.path(4, "all")).to eq("/home-bills/4?months=all")
  end

  it "says paid, due up to the due day, then late" do
    payment = {paid_on: "2026-10-08"}
    expect(described_class.status(bill, "2026-10", payment, today: Date.new(2026, 10, 20))).to eq(:paid)
    expect(described_class.status(bill, "2026-10", nil, today: Date.new(2026, 10, 10))).to eq(:due)
    expect(described_class.status(bill, "2026-10", nil, today: Date.new(2026, 10, 11))).to eq(:late)
  end

  describe ".suggest" do
    it "picks the payee's row nearest the due day" do
      bill[:payee_key] = "counterparty:7"
      rows = [row("2026-10-02", -150.00, counterparty_id: 7), row("2026-10-09", -190.00, counterparty_id: 7),
        row("2026-10-10", -182.40), row("2026-11-09", -190.00, counterparty_id: 7)]
      expect(described_class.suggest(bill, "2026-10", rows)).to eq(rows[1])
    end

    it "prefers the payee's row of the bill's own month, even far from a month-end due day" do
      bill.merge!(due_day: 31, payee_key: "counterparty:7")
      rows = [row("2026-07-08", -289.32, counterparty_id: 7), row("2026-08-11", -148.76, counterparty_id: 7)]
      expect(described_class.suggest(bill, "2026-07", rows)).to eq(rows[0])
    end

    it "without a payee, takes a spending row of its category near the expected amount" do
      bill[:category_id] = 21
      rows = [row("2026-10-09", -400.00, category_id: 21), row("2026-10-08", -175.00, category_id: 21),
        row("2026-10-10", -182.40, category_id: 22), row("2026-10-10", 182.40, category_id: 21)]
      expect(described_class.suggest(bill, "2026-10", rows)).to eq(rows[1])
    end

    it "suggests nothing without a payee or an expected amount, or with no row near" do
      expect(described_class.suggest(bill.merge(expected_cents: nil), "2026-10", [row("2026-10-10", -182.40)])).to be_nil
      expect(described_class.suggest(bill, "2026-10", [row("2026-09-10", -182.40)])).to be_nil
      near = row("2026-10-10", -182.40)
      expect(described_class.suggest(bill, "2026-10", [near])).to eq(near)
    end
  end

  it "offers the month's own rows, then rows near the due day, nearest first" do
    rows = [row("2026-09-20", -9.00), row("2026-09-30", -4.00), row("2026-10-08", -1.00), row("2026-10-11", -2.00),
      row("2026-10-30", -3.00), row("2026-11-10", -9.00), row("2026-10-12", 9.00)]
    expect(described_class.candidates(bill, "2026-10", rows).map { _1[:amount_cents] }).to eq([-200, -100, -300, -400])
  end
end
