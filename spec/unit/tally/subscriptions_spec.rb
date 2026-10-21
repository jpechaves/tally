# frozen_string_literal: true

RSpec.describe Tally::Subscriptions do
  def subscriptions(rows, month: "2026-09", dismissed: [], marked: [])
    described_class.new(rows, month:, dismissed:, marked:)
  end

  def monthly(amount, description, months:, day: "05", **attributes)
    months.map { insight_row("#{_1}-#{day}", amount, description, **attributes) }
  end

  let(:streamflix) { {counterparty_id: 7, counterparty_name: "StreamFlix", category_name: "Streaming"} }
  let(:gym) { {counterparty_id: 8, counterparty_name: "Academia Forte"} }

  it "lists charges in 3 of 4 months, card and Pix together, with monthly and yearly cost" do
    rows = monthly(-39.90, "STREAMFLIX", months: %w[2026-06 2026-07 2026-09], **streamflix) +
      monthly(-99.00, "Academia Forte", months: %w[2026-06 2026-07 2026-08], day: "10", **gym, account_name: "Nubank conta") +
      [insight_row("2026-09-11", -99.00, "ACADEMIA FORTE", **gym)]

    list = subscriptions(rows)
    expect(list.items.map(&:payee)).to eq(["Academia Forte", "StreamFlix"])
    expect(list.items.last).to have_attributes(
      key: "counterparty:7", category_name: "Streaming", accounts: ["Nubank cartão"], last_cents: 3_990,
      last_on: "2026-09-05", first_month: "2026-06", monthly_cents: 3_990, yearly_cents: 47_880,
      increase_cents: nil, stopped: false, manual: false
    )
    expect(list.items.first.accounts).to eq(["Nubank conta", "Nubank cartão"])
    expect(list).to have_attributes(monthly_cents: 13_890, yearly_cents: 166_680)
  end

  it "counts a foreign charge with its IOF row, so the rate changing doesn't break it" do
    cloudbox = {counterparty_id: 9, counterparty_name: "CloudBox"}
    rows = [["2026-07", -50.40], ["2026-08", -52.40], ["2026-09", -48.90]].flat_map do |month, amount|
      [insight_row("#{month}-03", amount, "CLOUDBOX", **cloudbox),
        insight_row("#{month}-03", (amount * 0.035).round(2), "IOF de \"CLOUDBOX\"", kind: "fee", **cloudbox)]
    end

    expect(subscriptions(rows).items.first).to have_attributes(payee: "CloudBox", last_cents: 5_061, ids: (1..6).to_a)
  end

  it "flags a price increase on a fixed price, or over 10% on one that varies" do
    rows = monthly(-39.90, "STREAMFLIX", months: %w[2026-06 2026-07 2026-08], **streamflix) +
      [insight_row("2026-09-05", -44.90, "STREAMFLIX", **streamflix)]
    expect(subscriptions(rows).items.first).to have_attributes(increase_cents: 500, monthly_cents: 4_490)
    expect(subscriptions(rows.drop(1)).items.first).to have_attributes(increase_cents: 500, first_month: "2026-07")

    varying = [-50.00, -52.00, -51.00, -53.00].zip(%w[2026-06 2026-07 2026-08 2026-09])
      .map { |amount, month| insight_row("#{month}-03", amount, "CLOUDBOX") }
    expect(subscriptions(varying).items.first.increase_cents).to be_nil
    varying << insight_row("2026-10-03", -60.00, "CLOUDBOX")
    expect(subscriptions(varying, month: "2026-10").items.first.increase_cents).to eq(700)
  end

  it "flags one missing for 2 months as stopped, out of the totals" do
    rows = monthly(-39.90, "STREAMFLIX", months: %w[2026-04 2026-05 2026-06 2026-07], **streamflix)

    expect(subscriptions(rows, month: "2026-08").items.first.stopped).to be(false)
    list = subscriptions(rows)
    expect(list.items.first).to have_attributes(stopped: true, last_on: "2026-07-05")
    expect(list.monthly_cents).to eq(0)
  end

  it "leaves out amounts that vary too much, installments, card fees without a merchant, and income" do
    rows = [-40.00, -90.00, -40.00].zip(%w[2026-07 2026-08 2026-09]).map { |amount, month| insight_row("#{month}-02", amount, "LOJA") } +
      %w[2026-07 2026-08 2026-09].each_with_index.map { |month, i| insight_row("#{month}-02", -100.00, "TV", installment_number: i + 1, installment_total: 10) } +
      monthly(-105.00, "Mensalidade - Plano do", months: %w[2026-07 2026-08 2026-09], kind: "fee") +
      monthly(5_000.00, "EMPRESA", months: %w[2026-07 2026-08 2026-09])

    expect(subscriptions(rows).items).to be_empty
  end

  it "keeps a dismissed one out and lists one marked by hand, even with a single charge" do
    rows = monthly(-39.90, "STREAMFLIX", months: %w[2026-07 2026-08 2026-09], **streamflix) +
      [insight_row("2026-09-20", -1_200.00, "SEGURO EXEMPLO")]

    list = subscriptions(rows, dismissed: ["counterparty:7"], marked: ["description:seguro exemplo", "description:nothing yet"])
    expect(list.items.map { [_1.payee, _1.manual, _1.monthly_cents] }).to eq([["SEGURO EXEMPLO", true, 120_000]])
  end

  it "only looks at months up to the one asked for" do
    rows = monthly(-39.90, "STREAMFLIX", months: %w[2026-07 2026-08 2026-09 2026-10], **streamflix)

    expect(subscriptions(rows, month: "2026-08").items).to be_empty
  end
end
