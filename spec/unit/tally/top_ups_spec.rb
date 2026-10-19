# frozen_string_literal: true

RSpec.describe Tally::TopUps do
  let(:paired) { {amount_cents: 17_874, other_cents: -100_000, other_currency: "BRL"} }
  let(:unpaired) { {amount_cents: 5_000, other_cents: nil, other_currency: nil} }

  it "prices a paired top-up by what its reais leg paid" do
    cost = described_class.cost_of(paired)

    expect(cost.rate).to eq(Rational(100_000, 17_874))
    expect(cost.convert(11_995)).to eq(67_109)
  end

  it "has no price for a top-up whose reais leg isn't imported" do
    expect(described_class.cost_of(unpaired)).to be_nil
    expect(described_class.cost_of(paired.merge(other_currency: "EUR"))).to be_nil
  end

  it "averages the paired top-ups by amount, not by count" do
    other = {amount_cents: 1_000, other_cents: -6_000, other_currency: "BRL"}
    average = described_class.average([paired, unpaired, other])

    expect(average).to have_attributes(cents: 18_874, paid_cents: 106_000)
    expect(described_class.average([unpaired])).to be_nil
  end
end
