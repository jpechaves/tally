# frozen_string_literal: true

RSpec.describe Tally::StatementGaps do
  def d(text) = Date.iso8601(text)

  describe ".statements" do
    it "finds the month no statement covers between two that are imported" do
      gaps = described_class.statements([d("2026-07-01")..d("2026-07-31"), d("2026-05-01")..d("2026-05-31")])

      expect(gaps).to eq([described_class::Gap.new(kind: "statement", from: d("2026-06-01"), to: d("2026-06-30"))])
      expect(gaps.first).to be_whole_months
    end

    it "finds nothing when the periods touch or overlap, in any order" do
      periods = [d("2026-03-01")..d("2026-03-31"), d("2026-01-01")..d("2026-02-10"), d("2026-02-01")..d("2026-02-28")]

      expect(described_class.statements(periods)).to eq([])
    end

    it "merges a period inside another, then the one that follows both" do
      periods = [d("2026-01-01")..d("2026-01-31"), d("2026-03-10")..d("2026-03-20"), d("2026-03-01")..d("2026-03-31"),
        d("2026-04-01")..d("2026-04-30")]

      expect(described_class.statements(periods).map { [_1.from, _1.to] }).to eq([[d("2026-02-01"), d("2026-02-28")]])
    end

    it "keeps a statement exported mid-month, and finds the days after it" do
      gaps = described_class.statements([d("2026-10-01")..d("2026-10-16"), d("2026-11-01")..d("2026-11-30")])

      expect(gaps.map { [_1.from, _1.to] }).to eq([[d("2026-10-17"), d("2026-10-31")]])
      expect(gaps.first).not_to be_whole_months
    end

    it "finds nothing before the first or after the last statement" do
      expect(described_class.statements([d("2026-07-01")..d("2026-07-31")])).to eq([])
      expect(described_class.statements([])).to eq([])
    end
  end

  describe ".bills" do
    it "finds the months with no bill due between two imported bills" do
      gaps = described_class.bills([d("2026-07-09"), d("2026-11-09"), d("2026-08-09")])

      expect(gaps).to eq([described_class::Gap.new(kind: "bill", from: d("2026-09-01"), to: d("2026-10-01"))])
      expect(described_class.bills([d("2026-07-09"), d("2026-09-09")]).map { [_1.from, _1.to] })
        .to eq([[d("2026-08-01"), d("2026-08-01")]])
    end

    it "finds nothing for bills a month apart, even when a due date moves" do
      expect(described_class.bills([d("2026-07-09"), d("2026-08-11"), d("2026-09-08"), d("2026-09-09")])).to eq([])
    end
  end
end
