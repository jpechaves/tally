# frozen_string_literal: true

RSpec.describe Tally::Search do
  it "folds accents, case and punctuation away" do
    expect(described_class.fold("João  da-Silva, Ltda.")).to eq("JOAO DA SILVA LTDA")
    expect(described_class.fold(nil)).to be_nil
  end
end
