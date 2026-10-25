# frozen_string_literal: true

RSpec.describe Tally::Balances do
  let(:days) { {"2026-09-30" => -1_000, "2026-10-05" => -2_000, "2026-10-10" => 50_000, "2026-10-20" => -3_000} }

  it "adds up the rows from zero without a check" do
    balance = described_class.call([], days)
    expect(balance.balance_cents).to eq(44_000)
    expect(balance.checks).to be_empty
  end

  it "starts from the newest check and adds the rows after it" do
    balance = described_class.call([{id: 1, checked_on: "2026-10-10", balance_cents: 216_102}], days)
    expect(balance.balance_cents).to eq(213_102)
    expect(balance.last_check.difference_cents).to be_nil
  end

  it "says how far each later check is from the one before plus the rows between" do
    checks = [{id: 1, checked_on: "2026-09-30", balance_cents: 100_000}, {id: 2, checked_on: "2026-10-10", balance_cents: 148_000},
      {id: 3, checked_on: "2026-10-20", balance_cents: 140_000}]
    balance = described_class.call(checks, days)
    expect(balance.checks.map(&:difference_cents)).to eq([nil, 0, -5_000])
    expect(balance.balance_cents).to eq(140_000)
  end
end
