# frozen_string_literal: true

RSpec.describe Tally::Pagination do
  it "reads a page number, 1 when it is missing or not one" do
    expect([nil, "", "0", "-2", "abc", "1e3", "3"].map { described_class.param(_1) }).to eq([1, 1, 1, 1, 1, 1, 3])
  end

  it "keeps the page within the pages there are" do
    expect(described_class.page(2, total: 250)).to have_attributes(number: 2, count: 3, offset: 100, limit: 100)
    expect(described_class.page(9, total: 250)).to have_attributes(number: 3, previous: 2, next: nil)
    expect(described_class.page(1, total: 0)).to have_attributes(number: 1, count: 1, previous: nil, next: nil)
  end

  it "slices a list already in memory" do
    page = described_class.page(3, total: 7, per_page: 3)
    expect(page.slice((1..7).to_a)).to eq([7])
  end

  it "links to a page, keeping the filters that are set" do
    path = described_class.path("/transactions", account: 3, month: nil, q: "joão silva")
    expect(path.call(2)).to eq("/transactions?account=3&q=jo%C3%A3o+silva&page=2")
    expect(described_class.path("/transactions", q: "").call(2)).to eq("/transactions?page=2")
  end
end
