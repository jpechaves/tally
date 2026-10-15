# frozen_string_literal: true

RSpec.describe Tally::Money do
  def money(cents, currency = "BRL") = described_class.new(cents, currency)

  describe ".new" do
    it "holds whole cents and a currency" do
      amount = money(12_345)

      expect(amount.cents).to eq(12_345)
      expect(amount.currency).to eq("BRL")
      expect(amount).to be_frozen
    end

    it "refuses floats and other non-integers" do
      expect { money(12.5) }.to raise_error(TypeError, /Integer cents/)
      expect { money(BigDecimal("1")) }.to raise_error(TypeError)
      expect { money("100") }.to raise_error(TypeError)
    end

    it "refuses a malformed currency" do
      expect { money(1, "brl") }.to raise_error(ArgumentError)
      expect { money(1, "R$") }.to raise_error(ArgumentError)
    end
  end

  describe ".parse" do
    context "with a comma decimal mark (Brazilian statements and forms)" do
      {
        "1.234,56" => 123_456,
        "-64,66" => -6_466,
        "- 7,06" => -706,
        "R$ 12,90" => 1_290,
        "-R$ 1.000.000,00" => -100_000_000,
        "1234,5" => 123_450,
        "0,01" => 1,
        "300" => 30_000,
        "+15,00" => 1_500,
        "  289,90\n" => 28_990
      }.each do |text, cents|
        it "reads #{text.inspect} as #{cents} cents" do
          expect(described_class.parse(text).cents).to eq(cents)
        end
      end
    end

    context "with a dot decimal mark (Nubank account CSV)" do
      {
        "-518.54" => -51_854,
        "1,234.56" => 123_456,
        "4000" => 400_000,
        "0.1" => 10
      }.each do |text, cents|
        it "reads #{text.inspect} as #{cents} cents" do
          expect(described_class.parse(text, decimal: ".").cents).to eq(cents)
        end
      end
    end

    it "rejects more than two decimal places instead of rounding" do
      expect { described_class.parse("1,005") }.to raise_error(Tally::Money::ParseError, /2 decimal places/)
      expect { described_class.parse("0.123", decimal: ".") }.to raise_error(Tally::Money::ParseError)
    end

    it "rejects text that isn't an exact amount" do
      ["", "abc", "1,2,3", "12.34", "1.23,45", "--1,00", "1e3", "1.2345,00", ",50"].each do |text|
        expect { described_class.parse(text) }.to raise_error(Tally::Money::ParseError), text.inspect
      end
    end

    it "rejects non-strings, so floats never sneak in" do
      expect { described_class.parse(12.34) }.to raise_error(Tally::Money::ParseError)
    end

    it "carries the given currency" do
      expect(described_class.parse("10.00", decimal: ".", currency: "USD")).to eq(money(1_000, "USD"))
    end

    it "is exact where floats are not" do
      expect(described_class.parse("0,10") + described_class.parse("0,20")).to eq(described_class.parse("0,30"))
    end
  end

  describe "arithmetic" do
    it "adds, subtracts and negates" do
      expect(money(1_000) + money(250)).to eq(money(1_250))
      expect(money(1_000) - money(1_250)).to eq(money(-250))
      expect(-money(300)).to eq(money(-300))
      expect(money(-300).abs).to eq(money(300))
    end

    it "multiplies by whole numbers only" do
      expect(money(28_990) * 2).to eq(money(57_980))
      expect { money(100) * 1.5 }.to raise_error(TypeError, /allocate/)
    end

    it "never mixes currencies" do
      expect { money(100) + money(100, "USD") }.to raise_error(Tally::Money::CurrencyMismatch)
      expect { money(100) < money(100, "USD") }.to raise_error(Tally::Money::CurrencyMismatch)
    end

    it "refuses plain numbers" do
      expect { money(100) + 1 }.to raise_error(TypeError)
    end

    it "sums a list, with an empty list being zero" do
      expect(described_class.sum([money(1), money(2), money(-5)])).to eq(money(-2))
      expect(described_class.sum([])).to eq(described_class.zero)
    end
  end

  describe "comparison and equality" do
    it "orders amounts" do
      expect([money(5), money(-3), money(0)].sort).to eq([money(-3), money(0), money(5)])
      expect(money(5)).to be > money(4)
    end

    it "treats different currencies as unequal without raising" do
      expect(money(100)).not_to eq(money(100, "USD"))
      expect(money(100)).not_to eq(100)
    end

    it "works as a hash key" do
      expect({money(100) => :a}[money(100)]).to eq(:a)
    end

    it "knows its sign" do
      expect(money(0)).to be_zero
      expect(money(1)).to be_positive
      expect(money(-1)).to be_negative
    end
  end

  describe "#allocate" do
    it "splits by weights and always adds back up to the total" do
      parts = money(100).allocate([1, 1, 1])

      expect(parts.map(&:cents)).to eq([34, 33, 33])
      expect(described_class.sum(parts)).to eq(money(100))
    end

    it "gives leftover cents to the largest remainders, not the first parts" do
      # 10 split 1:3:6 is 1 / 3 / 6 exactly; 11 is 1.1 / 3.3 / 6.6, so the extra cent goes to 6.6
      expect(money(11).allocate([1, 3, 6]).map(&:cents)).to eq([1, 3, 7])
    end

    it "matches the savings planner example in the docs" do
      # A R$ 1.500,00 gap split across R$ 2.500,00 and R$ 600,00 of cuttable spending.
      parts = money(150_000).allocate([250_000, 60_000])

      expect(parts.map(&:cents)).to eq([120_968, 29_032])
    end

    it "keeps the sign of a negative amount" do
      expect(money(-100).allocate([1, 1, 1]).map(&:cents)).to eq([-34, -33, -33])
    end

    it "allows zero weights" do
      expect(money(100).allocate([0, 1, 0]).map(&:cents)).to eq([0, 100, 0])
    end

    it "rejects invalid weights" do
      expect { money(100).allocate([]) }.to raise_error(ArgumentError)
      expect { money(100).allocate([0, 0]) }.to raise_error(ArgumentError)
      expect { money(100).allocate([1, -1]) }.to raise_error(ArgumentError)
      expect { money(100).allocate([0.5, 0.5]) }.to raise_error(ArgumentError)
    end

    it "adds up for many random amounts and weights" do
      random = Random.new(2026)

      500.times do
        total = money(random.rand(-1_000_000..1_000_000))
        weights = Array.new(random.rand(1..12)) { random.rand(0..10_000) }
        weights[0] += 1 if weights.sum.zero?

        parts = total.allocate(weights)

        expect(described_class.sum(parts)).to eq(total)
        # each part is within one cent of its exact proportional share
        parts.zip(weights).each do |part, weight|
          expect((part.cents * weights.sum - total.cents * weight).abs).to be < weights.sum
        end
      end
    end
  end

  describe "#split" do
    it "splits into parts that differ by at most a cent" do
      expect(money(1_000).split(3).map(&:cents)).to eq([334, 333, 333])
      expect { money(1).split(0) }.to raise_error(ArgumentError)
    end
  end

  describe "#format" do
    {
      0 => "R$ 0,00",
      5 => "R$ 0,05",
      123_456 => "R$ 1.234,56",
      -706 => "-R$ 7,06",
      100_000_000 => "R$ 1.000.000,00"
    }.each do |cents, text|
      it "formats #{cents} cents as #{text.inspect}" do
        expect(money(cents).format).to eq(text)
        expect(money(cents).to_s).to eq(text)
      end
    end

    it "uses the currency code when there is no symbol" do
      expect(money(1_050, "USD").format).to eq("USD 10,50")
    end

    it "round-trips through .parse" do
      [0, 1, -1, 99, 123_456, -987_654_321].each do |cents|
        expect(described_class.parse(money(cents).format).cents).to eq(cents)
      end
    end
  end

  it "exposes the exact decimal value" do
    expect(money(-51_854).to_d).to eq(BigDecimal("-518.54"))
  end
end
