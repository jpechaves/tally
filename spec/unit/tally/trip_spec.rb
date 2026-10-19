# frozen_string_literal: true

RSpec.describe Tally::Trip do
  let(:trip) { {starts_on: "2026-03-10", ends_on: "2026-03-18", account_ids: [], choices: {}} }
  let(:itau) { {account_id: 2, account_name: "Itaú cartão", currency: "BRL"} }
  let(:global) { {account_id: 3, account_name: "Conta Global", currency: "USD"} }
  let(:cost) { Tally::TopUps::Cost.new(cents: 100_000, paid_cents: 520_000) } # R$ 5,20 per US$

  def row(occurred_on, amount, description, **attributes)
    insight_row(occurred_on, amount, description, currency: "BRL", purchased_on: nil, **attributes)
  end

  def flight(number, occurred_on, purchased_on: "2026-01-15")
    row(occurred_on, -500.00, "LATAM AIR", purchased_on:, installment_number: number, installment_total: 6,
      category_id: 61, category_name: "Passagens", parent_id: 6, parent_name: "Viagem", **itau)
  end

  def build(rows, installments: [], costs: {3 => cost}, **choices)
    described_class.new(trip.merge(**choices), rows, installments:, costs:)
  end

  it "adds up the issue's example: a flight in installments, dollars at the top-up rate, a car and its IOF" do
    flights = [flight(1, "2026-01-20"), flight(2, "2026-02-20")]
    rows = [
      row("2026-03-11", -800.00, "HOTEL EXEMPLO", category_id: 62, category_name: "Hospedagem", parent_id: 6, parent_name: "Viagem", **global),
      row("2026-03-12", -900.00, "LOCADORA EXEMPLO"),
      row("2026-03-12", -39.15, "IOF de \"LOCADORA EXEMPLO\"", kind: "fee"),
      row("2026-03-25", -100.00, "MERCADO"),
      row("2026-03-15", 5_000.00, "SALARIO")
    ]

    result = build(rows, installments: flights, choices: {flights.first[:id] => true})
    expect(result.rows.map { _1[:description] }).to eq(["LATAM AIR", "LATAM AIR", "HOTEL EXEMPLO", "LOCADORA EXEMPLO", "IOF de \"LOCADORA EXEMPLO\""])
    expect(result.future).to eq([Tally::Trip::Future.new(description: "LATAM AIR", count: 4, cents: 200_000)])
    expect(result).to have_attributes(total_cents: 809_915, foreign: {"USD" => 80_000}, foreign_reais_cents: 416_000,
      iof_cents: 3_915, unpriced: false)
    expect(result.by_category.map(&:to_h)).to eq([
      {id: 6, name: "Viagem", cents: 716_000, own_cents: nil, currency: nil},
      {id: nil, name: nil, cents: 93_915, own_cents: nil, currency: nil}
    ])
    expect(result.by_account.map(&:to_h)).to eq([
      {id: 3, name: "Conta Global", cents: 416_000, own_cents: 80_000, currency: "USD"},
      {id: 2, name: "Itaú cartão", cents: 300_000, own_cents: 300_000, currency: "BRL"},
      {id: 1, name: "Nubank cartão", cents: 93_915, own_cents: 93_915, currency: "BRL"}
    ])
    expect(result.added?(flights.first)).to be(true)
    expect(result.added?(rows[1])).to be(false)
  end

  it "subtracts IOF refunds, and keeps dollars out of the total without a top-up to price them" do
    rows = [
      row("2026-03-12", -10.00, "IOF de compra internacional", kind: "fee"),
      row("2026-03-16", 4.00, "IOF de volta de LOJA", kind: "refund"),
      row("2026-03-11", -50.00, "MUSEU EXEMPLO", **global)
    ]

    result = build(rows, costs: {})
    expect(result).to have_attributes(iof_cents: 600, total_cents: 600, foreign: {"USD" => 5_000}, foreign_reais_cents: 0, unpriced: true)
  end

  it "keeps to the trip's accounts, and to your choices: a removed row and a whole removed purchase" do
    flights = [flight(1, "2026-03-11", purchased_on: "2026-03-11"), flight(2, "2026-04-11", purchased_on: "2026-03-11")]
    rows = [row("2026-03-12", -900.00, "LOCADORA EXEMPLO"), row("2026-03-13", -20.00, "CAFE", **itau), flights.first]

    expect(build(rows, installments: flights, account_ids: [2]).ids).to eq([flights[0][:id], rows[1][:id], flights[1][:id]])
    result = build(rows, installments: flights, choices: {rows[1][:id] => false, flights[1][:id] => false})
    expect(result.ids).to eq([rows[0][:id]])
    expect(result.future).to be_empty
  end
end
