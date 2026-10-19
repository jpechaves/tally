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

  it "leaves a monthly card fee to the fees signal, which nets its discount" do
    rows = %w[2026-06 2026-07 2026-08 2026-09].flat_map do |month|
      [insight_row("#{month}-02", -105.00, "Mensalidade - Plano do", kind: "fee"),
        insight_row("#{month}-14", 52.50, "Redução Mensalidade - P", kind: "fee")]
    end

    expect(suggestions(rows).map(&:signal)).to eq(["fees"])
    expect(suggestions(rows).first.monthly_cents).to eq(5_250)
  end

  it "doesn't take a charge repeated on most days for a duplicate" do
    rows = (10..15).map { insight_row("2026-09-#{_1}", -14.00, "ESTACIONAMENTO EXEMPLO") }

    expect(suggestions(rows).map(&:signal)).not_to include("duplicate")
  end

  it "flags the same payee and amount twice on the same or the next day, until dismissed" do
    rows = [
      insight_row("2026-09-15", -189.90, "ACADEMIA EXEMPLO"),
      insight_row("2026-09-15", -189.90, "ACADEMIA EXEMPLO"),
      insight_row("2026-09-16", -189.90, "ACADEMIA EXEMPLO"),
      insight_row("2026-09-25", -50.00, "LOJA"),
      insight_row("2026-09-29", -50.00, "LOJA")
    ]

    duplicate = suggestions(rows).find { _1.signal == "duplicate" }
    expect(duplicate).to have_attributes(key: "duplicate:description:academia exemplo:-18990", monthly_cents: 37_980,
      facts: {payee: "ACADEMIA EXEMPLO", cents: 18_990, count: 3, dates: ["2026-09-15", "2026-09-16"]})
    expect(suggestions(rows).count { _1.signal == "duplicate" }).to eq(1)
    expect(suggestions(rows, dismissed: [duplicate.key]).map(&:signal)).not_to include("duplicate")
  end

  it "sums up the month's new installment purchases, and leaves installments out of recurring" do
    rows = [
      insight_row("2026-09-18", -1_050.00, "Hotel Exemplo", installment_number: 1, installment_total: 6),
      insight_row("2026-09-20", -60.00, "Doceria Exemplo", installment_number: 1, installment_total: 2),
      insight_row("2026-09-21", -15.00, "Banca Exemplo", installment_number: 1, installment_total: 1),
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

  describe "at each threshold" do
    def signals(rows) = suggestions(rows).map(&:signal)

    it "needs a category over 5% of spending, not at it, counting only first installments" do
      rows = [insight_row("2026-09-02", -1_900.00, "MERCADO", **in_category(:market)),
        insight_row("2026-09-03", -100.00, "IFOOD", **in_category(:delivery))]
      expect(signals(rows)).not_to include("big")

      rows << insight_row("2026-09-04", -60.00, "IFOOD", **in_category(:delivery), installment_number: 1, installment_total: 3)
      expect(suggestions(rows).find { _1.signal == "big" }.facts).to include(count: 2, cents: 16_000)

      rows[-1] = insight_row("2026-09-04", -60.00, "IFOOD", **in_category(:delivery), installment_number: 2, installment_total: 3)
      expect(signals(rows)).not_to include("big")
    end

    it "needs growth over 25%, and of at least R$ 100" do
      market = ->(amounts) { amounts.each_with_index.map { |amount, i| insight_row("2026-0#{6 + i}-10", amount, "MERCADO", **in_category(:market)) } }

      expect(signals(market.([-400.00, -400.00, -400.00, -500.00]))).not_to include("growth") # exactly 25%
      expect(signals(market.([-300.00, -300.00, -300.00, -400.00]))).to include("growth") # exactly R$ 100
      expect(signals(market.([-300.00, -300.00, -300.00, -399.99]))).not_to include("growth")
    end

    it "takes the median of the months as the typical charge, allowing exactly 10% around it" do
      payee = ->(amounts) { amounts.each_with_index.map { |amount, i| insight_row("2026-0#{6 + i}-10", amount, "CLUBE EXEMPLO") } }

      # Sorted 89, 98, 99, 99: the median is 99, and 89 is more than 10% below it.
      expect(signals(payee.([-89.00, -98.00, -99.00, -99.00]))).not_to include("recurring")
      expect(signals(payee.([-90.00, -100.00, -100.00, -100.00]))).to include("recurring")
    end

    it "looks back only 4 months, this one included" do
      rows = history(-50.00, "CLUBE EXEMPLO", months: %w[2026-05 2026-08 2026-09])

      expect(signals(rows)).not_to include("recurring")
      expect(signals(rows + history(-50.00, "CLUBE EXEMPLO", months: %w[2026-06]))).to include("recurring")
    end

    it "needs a charge this month, not one netted out by a refund" do
      rows = history(-50.00, "CLUBE EXEMPLO") + [
        insight_row("2026-09-10", -50.00, "CLUBE EXEMPLO"),
        insight_row("2026-09-11", 50.00, "CLUBE EXEMPLO", kind: "refund")
      ]

      expect(signals(rows)).not_to include("recurring")
      expect(suggestions(history(-50.00, "CLUBE EXEMPLO"))).to be_empty
    end

    it "counts only purchases under R$ 50, at least 8 of them" do
      parking = ->(count, amount, **attributes) { (1..count).map { insight_row("2026-09-%02d" % (_1 * 3), amount, "ESTACIONAMENTO", **attributes) } }

      expect(signals(parking.(7, -14.00))).not_to include("small")
      expect(signals(parking.(8, -50.00))).not_to include("small")
      expect(signals(parking.(8, -49.99))).to include("small")
      expect(signals(parking.(8, -14.00, kind: "fee"))).not_to include("small")
    end

    it "takes up to 3 equal charges, on the same or the next day, for a duplicate" do
      charges = ->(*days) { days.map { insight_row("2026-09-#{_1}", -30.00, "LOJA EXEMPLO") } }

      expect(signals(charges.(10, 11))).to include("duplicate")
      expect(suggestions(charges.(10, 11, 20)).find { _1.signal == "duplicate" }.monthly_cents).to eq(6_000)
      expect(signals(charges.(10, 12))).not_to include("duplicate")
      expect(signals(charges.(10, 11, 20, 25))).not_to include("duplicate")
    end

    it "lists the 5 biggest new installment purchases" do
      rows = (1..6).map { insight_row("2026-09-0#{_1}", -10.00 * _1, "LOJA #{_1}", installment_number: 1, installment_total: 2) }

      expect(suggestions(rows).first.facts[:biggest]).to eq(["LOJA 6 (2×)", "LOJA 5 (2×)", "LOJA 4 (2×)", "LOJA 3 (2×)", "LOJA 2 (2×)"])
    end
  end
end
