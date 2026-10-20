# frozen_string_literal: true

RSpec.describe Tally::Search do
  it "folds accents, case and punctuation away" do
    expect(described_class.fold("João  da-Silva, Ltda.")).to eq("JOAO DA SILVA LTDA")
    expect(described_class.fold(nil)).to be_nil
  end

  it "reads a search as an amount when all of it is one: cents, and a sign only if typed" do
    expect(described_class.amount("45,90")).to eq([nil, 4590])
    expect(described_class.amount("45.90")).to eq([nil, 4590])
    expect(described_class.amount("1.234,56")).to eq([nil, 123_456])
    expect(described_class.amount("1,234.56")).to eq([nil, 123_456])
    expect(described_class.amount("R$ 45,90")).to eq([nil, 4590])
    expect(described_class.amount("US$ 12.50")).to eq([nil, 1250])
    expect(described_class.amount("-45,90")).to eq([-1, 4590])
    expect(described_class.amount("- R$ 45,90")).to eq([-1, 4590])
    expect(described_class.amount("+45")).to eq([1, 4500])
    expect(described_class.amount("45")).to eq([nil, 4500])
    expect(described_class.amount("45,9x")).to be_nil
    expect(described_class.amount("1,2,3")).to be_nil
    expect(described_class.amount("padaria")).to be_nil
  end
end
