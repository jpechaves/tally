# frozen_string_literal: true

RSpec.describe Tally::Cuts do
  def suggestions(rows, month: "2026-09", dismissed: [])
    described_class.new(rows, month:, dismissed:).suggestions
  end

  def history(amount, description, months: %w[2026-06 2026-07 2026-08], day: "10", **attributes)
    months.map { insight_row("#{_1}-#{day}", amount, description, **attributes) }
  end

  it "flags a discretionary category over 5% of spending, worth its maximum cut" do
    rows = [
      insight_row("2026-09-02", -2_000.00, "MERCADO", **in_category(:market)),
      insight_row("2026-09-03", -300.00, "IFOOD", **in_category(:delivery)),
      insight_row("2026-09-04", -200.00, "IFOOD", **in_category(:delivery))
    ]

    big = suggestions(rows).find { _1.signal == "big" }
    expect(big).to have_attributes(key: "big:category:11", monthly_cents: 25_000,
      facts: {name: "Delivery", count: 2, cents: 50_000, share: 20.0, pct: 50})
    expect(suggestions(rows).map(&:signal)).not_to include("growth") # no history
  end

  it "flags growth over 25% and R$ 100 against a full 3-month average" do
    rows = history(-400.00, "MERCADO", **in_category(:market)) +
      [insight_row("2026-09-10", -600.00, "MERCADO", **in_category(:market))]

    growth = suggestions(rows).find { _1.signal == "growth" }
    expect(growth).to have_attributes(monthly_cents: 20_000,
      facts: {name: "Supermercado", cents: 60_000, average_cents: 40_000, pct: 50, from: "2026-06", to: "2026-08"})

    rows[-1] = insight_row("2026-09-10", -480.00, "MERCADO", **in_category(:market)) # +20%: quiet
    expect(suggestions(rows).map(&:signal)).not_to include("growth")
  end

  it "finds recurring charges, within 10% of the typical amount" do
    rows = history(-119.90, "ACADEMIA EXEMPLO", months: %w[2026-06 2026-08], **in_category(:gym)) +
      [insight_row("2026-09-15", -129.90, "ACADEMIA EXEMPLO", **in_category(:gym))]

    recurring = suggestions(rows).find { _1.signal == "recurring" }
    expect(recurring).to have_attributes(key: "recurring:description:academia exemplo", monthly_cents: 12_990,
      facts: {payee: "ACADEMIA EXEMPLO", cents: 12_990, months: 3, window: 4})

    rows << insight_row("2026-07-15", -300.00, "ACADEMIA EXEMPLO", **in_category(:gym))
    expect(suggestions(rows).map(&:signal)).not_to include("recurring")
  end

  it "flags 8 or more small purchases at one payee" do
    rows = (1..8).map { insight_row("2026-09-%02d" % _1, -14.00, "ESTACIONAMENTO EXEMPLO #{_1}", **in_category(:parking)) }

    small = suggestions(rows).find { _1.signal == "small" }
    expect(small).to have_attributes(monthly_cents: 11_200,
      facts: {payee: "ESTACIONAMENTO EXEMPLO 1", count: 8, cents: 11_200, average_cents: 1_400})
  end

  it "adds up fees, interest and financing" do
    rows = [
      insight_row("2026-09-02", -105.00, "Mensalidade - Plano do", kind: "fee"),
      insight_row("2026-09-14", 52.50, "Redução Mensalidade - P", kind: "fee"),
      insight_row("2026-09-08", -635.20, "FINANCEIRA EXEMPLO", kind: "bill_payment", **in_category(:financing))
    ]

    expect(suggestions(rows).find { _1.signal == "fees" }).to have_attributes(monthly_cents: 68_770, ids: [1, 2, 3])
  end

  it "flags the same payee and amount twice within 2 days, until dismissed" do
    rows = [
      insight_row("2026-09-15", -189.90, "ACADEMIA EXEMPLO"),
      insight_row("2026-09-15", -189.90, "ACADEMIA EXEMPLO"),
      insight_row("2026-09-25", -50.00, "LOJA"),
      insight_row("2026-09-29", -50.00, "LOJA")
    ]

    duplicate = suggestions(rows).find { _1.signal == "duplicate" }
    expect(duplicate).to have_attributes(key: "duplicate:description:academia exemplo:-18990", monthly_cents: 18_990,
      facts: {payee: "ACADEMIA EXEMPLO", cents: 18_990, count: 2, dates: ["2026-09-15"]})
    expect(suggestions(rows).count { _1.signal == "duplicate" }).to eq(1)
    expect(suggestions(rows, dismissed: [duplicate.key]).map(&:signal)).not_to include("duplicate")
  end

  it "sums up the month's new installment purchases, and leaves installments out of recurring" do
    rows = [
      insight_row("2026-09-18", -1_050.00, "Hotel Exemplo", installment_number: 1, installment_total: 6),
      insight_row("2026-09-20", -60.00, "Doceria Exemplo", installment_number: 1, installment_total: 2),
      *%w[2026-06 2026-07 2026-08 2026-09].each_with_index.map do |month, index|
        insight_row("#{month}-02", -249.99, "LOJA EXEMPLO", installment_number: index + 3, installment_total: 12)
      end
    ]

    expect(suggestions(rows).map(&:signal)).to eq(["installments"])
    expect(suggestions(rows).first).to have_attributes(
      monthly_cents: 111_000,
      facts: {count: 2, cents: 111_000, later_cents: 531_000, biggest: ["Hotel Exemplo (6×)", "Doceria Exemplo (2×)"]}
    )
  end

  it "ignores transfers and income, and sorts by the estimate" do
    rows = [
      insight_row("2026-09-01", -5_000.00, "Pagamento de fatura", kind: "transfer"),
      insight_row("2026-09-01", 9_000.00, "EMPRESA"),
      insight_row("2026-09-02", -105.00, "Mensalidade", kind: "fee"),
      insight_row("2026-09-03", -400.00, "IFOOD", **in_category(:delivery))
    ]

    expect(suggestions(rows).map { [_1.signal, _1.monthly_cents] }).to eq([["big", 20_000], ["fees", 10_500]])
  end
end
