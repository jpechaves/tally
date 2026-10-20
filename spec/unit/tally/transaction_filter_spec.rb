# frozen_string_literal: true

RSpec.describe Tally::TransactionFilter do
  it "reads the filters from a query, ignoring values that aren't valid" do
    filter = described_class.parse({account: "3", month: "2026-08", category: "12", kind: "spending"})
    expect(filter).to have_attributes(account: 3, month: "2026-08", category: 12, kind: "spending")

    filter = described_class.parse({account: "x", month: "2026-13", category: "1; drop", kind: "anything"})
    expect(filter).to have_attributes(account: nil, month: nil, category: nil, kind: nil)
    expect(filter.any?).to be(false)

    expect(described_class.parse({category: "none"}).category).to eq("none")
  end

  it "links to the filtered transactions, and to their pages" do
    filter = described_class.new(month: "2026-08", category: 12, kind: "spending")
    expect(filter.path).to eq("/transactions?month=2026-08&category=12&kind=spending")
    expect(filter.pages.call(2)).to eq("/transactions?month=2026-08&category=12&kind=spending&page=2")
    expect(described_class.new.path).to eq("/transactions")
  end

  it "reads back the filters its links carry" do
    filter = described_class.new(account: 1, month: "2026-08", category: "none", kind: "income")
    query = URI.decode_www_form(URI(filter.path).query).to_h.transform_keys(&:to_sym)
    expect(described_class.parse(query)).to eq(filter)
  end

  it "reads a search, stripped and at most 100 characters, as one more filter" do
    expect(described_class.parse({q: "  padaria exemplo "}).q).to eq("padaria exemplo")
    expect(described_class.parse({q: "x" * 150}).q.length).to eq(100)
    expect(described_class.parse({q: "   "}).q).to be_nil

    filter = described_class.new(month: "2026-08", category: "none", q: "mercado")
    expect(filter.path).to eq("/transactions?month=2026-08&category=none&q=mercado")
    expect(filter.carried).to eq({})
  end
end
