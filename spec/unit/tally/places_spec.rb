# frozen_string_literal: true

RSpec.describe Tally::Places do
  subject(:places) do
    described_class.new([
      {"name" => "São Paulo", "lat" => -23.55, "lon" => -46.63},
      {"name" => "Rio de Janeiro", "lat" => -22.91, "lon" => -43.17},
      {"name" => "Lisboa", "lat" => 38.72, "lon" => -9.14, "aliases" => ["Lisbon"]},
      {"name" => "Toronto", "lat" => 43.65, "lon" => -79.38}
    ])
  end

  def row(description, location: nil, currency: "BRL") = {description:, location:, currency:}

  it "finds a city however the bank spelled or cut it" do
    expect(["SAO PAULO", "Sao Paulo", "So Paulo", "RIO DE JANEIR", "lisbon"].map { places.find(_1)&.name })
      .to eq(["São Paulo", "São Paulo", "São Paulo", "Rio de Janeiro", "Lisboa"])
    expect([nil, "", "SAO", "CURITIBA"].map { places.find(_1) }).to all(be_nil)
  end

  it "puts each place once, from the card's city or the end of a dollar purchase, and lists the rest" do
    found = places.of([
      row("PADARIA EXEMPLO", location: "SAO PAULO"),
      row("LOJA EXEMPLO", location: "So Paulo"),
      row("CAFE EXEMPLO", location: "CURITIBA"),
      row("Loja Exemplo TORONTO", currency: "USD"),
      row("Some Shop Rio de Janeiro", currency: "USD"),
      row("Online Exemplo", currency: "USD"),
      row("MERCADO EXEMPLO")
    ])

    expect(found.places.map(&:name)).to eq(["São Paulo", "Toronto", "Rio de Janeiro"])
    expect(found.missing).to eq(["CURITIBA", "Online Exemplo"])
  end

  it "ships a table of public city coordinates" do
    expect(described_class.default.find("RIO DE JANEIR")).to have_attributes(name: "Rio de Janeiro", lat: -22.92, lon: -43.23)
  end
end
