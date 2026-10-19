# frozen_string_literal: true

RSpec.describe Tally::Review do
  def row(id, description, amount_cents, **attributes)
    {id:, description:, amount_cents:, category_id: nil, category_source: "none", counterparty_id: nil}.merge(attributes)
  end

  it "groups by counterparty, or by the description's words, biggest total first" do
    groups = described_class.groups([
      row(1, "FARMACIA EXEMPLO 4021", -6_347),
      row(2, "FARMACIA EXEMPLO 1187", -2_000),
      row(3, "ENERGIA EXEMPLO S.A.", -18_743, counterparty_id: 7, counterparty_name: "ENERGIA EXEMPLO S.A."),
      row(4, "Conta de luz", -1_000, counterparty_id: 7, counterparty_name: "ENERGIA EXEMPLO S.A.")
    ])

    expect(groups.map { [_1.label, _1.ids, _1.total_cents] }).to eq([
      ["ENERGIA EXEMPLO S.A.", [3, 4], -19_743],
      ["FARMACIA EXEMPLO 4021", [1, 2], -8_347]
    ])
    expect(groups.first).to have_attributes(counterparty_id: 7, pattern: nil)
  end

  it "suggests the bank's category when the whole group shares it" do
    groups = described_class.groups([
      row(1, "MERCADO EXEMPLO", -100, category_id: 5, category_source: "bank", category_name: "Supermercado"),
      row(2, "MERCADO EXEMPLO", -200, category_id: 5, category_source: "bank", category_name: "Supermercado"),
      row(3, "LOJA EXEMPLO 03/10", -300, category_id: 6, category_source: "bank", category_name: "Casa"),
      row(4, "LOJA EXEMPLO 04/10", -300)
    ])

    expect(groups.map { [_1.label, _1.suggested_category_id, _1.suggested_category_name] })
      .to eq([["LOJA EXEMPLO 03/10", nil, nil], ["MERCADO EXEMPLO", 5, "Supermercado"]])
  end

  it "learns a pattern that matches the group's other descriptions, and not longer words" do
    regex = Tally::Categorizer.regex(described_class.pattern("PET EXEMPLO*PETL 04/10"))

    expect(regex).to match("pet exemplo*petl 05/10").and match("pet exemplo petl")
    expect(regex).not_to match("pet exemplo petlove")
    expect(regex).not_to match("super pet exemplo petl")
  end

  it "groups and matches a description with no letters by all of it" do
    groups = described_class.groups([row(1, "123-456", -100), row(2, "123-456", -50), row(3, "123-457", -10)])

    expect(groups.map { [_1.key, _1.ids, _1.pattern] }).to eq([
      ["description:123-456", [1, 2], "^123\\-456$"],
      ["description:123-457", [3], "^123\\-457$"]
    ])
  end

  it "labels a group by its first row, and keeps a total per currency" do
    groups = described_class.groups([
      row(1, "LOJA EXEMPLO 1", -100, currency: "USD"),
      row(2, "LOJA EXEMPLO 2", -300),
      row(3, "LOJA EXEMPLO 3", -50)
    ])

    expect(groups.first).to have_attributes(label: "LOJA EXEMPLO 1", total_cents: -450, totals: {"USD" => -100, "BRL" => -350})
  end

  it "orders groups of the same size by their label" do
    groups = described_class.groups([row(1, "ZETA", -100), row(2, "ALFA", 100)])

    expect(groups.map(&:label)).to eq(%w[ALFA ZETA])
  end
end
