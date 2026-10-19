# frozen_string_literal: true

RSpec.describe Tally::Exchange do
  # A Conta Global top-up of US$ 178,74 at 0,185 USD per BRL, paid with R$ 1.000,00.
  let(:dollars) { {amount_cents: 17_874, exchange_currency: "BRL", exchange_rate: "5.405405"} }
  let(:reais) { {amount_cents: -100_000} }

  def legs?(a, b, currency_a = "USD", currency_b = "BRL") = described_class.legs?(a, b, currency_a, currency_b)

  it "matches legs in one currency by opposite amounts" do
    expect(legs?({amount_cents: -500}, {amount_cents: 500}, "BRL", "BRL")).to be(true)
    expect(legs?({amount_cents: -500}, {amount_cents: 501}, "BRL", "BRL")).to be(false)
  end

  it "matches legs in two currencies through the rate either leg prints" do
    expect(legs?(dollars, reais)).to be(true)
    expect(legs?(reais, dollars, "BRL", "USD")).to be(true)
  end

  it "converts a priced leg that takes money out, too" do
    withdrawal = dollars.merge(amount_cents: -17_874)

    expect(legs?(withdrawal, {amount_cents: 100_000})).to be(true)
  end

  it "needs the legs to go opposite ways" do
    expect(legs?(dollars, reais.merge(amount_cents: 100_000))).to be(false)
  end

  it "needs a rate into the other leg's currency" do
    expect(legs?(dollars.merge(exchange_rate: nil), reais)).to be(false)
    expect(legs?(dollars.merge(exchange_currency: "EUR"), reais)).to be(false)
    expect(legs?(reais.merge(exchange_rate: "0.185", exchange_currency: "EUR"), dollars.except(:exchange_rate), "BRL", "USD")).to be(false)
  end

  it "allows the other leg 2% under to 8% over the converted amount, for IOF and rounding" do
    # US$ 178,74 at 5,405405 is R$ 966,16; 98% of it is R$ 946,84 and 108% R$ 1.043,45.
    expect([-94_683, -94_684, -104_345, -104_346].map { legs?(dollars, {amount_cents: _1}) })
      .to eq([false, true, true, false])
  end
end
