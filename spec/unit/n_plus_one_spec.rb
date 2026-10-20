# frozen_string_literal: true

# The N+1 check every request spec runs through (spec/support/n_plus_one.rb).
RSpec.describe NPlusOne, :db do
  let(:accounts) { Hanami.app["repos.account_repo"] }

  it "fails when one line of app code runs the same query once per row" do
    expect { described_class.check { 6.times { accounts.find(_1) } } }
      .to raise_error(NPlusOne::Error, /\A6x app\/repos\/account_repo\.rb#find: SELECT /)
  end

  it "lets a few repeats and the allowed ones through" do
    expect(described_class.check { 5.times { accounts.find(_1) } }).to eq(5)
    expect(described_class.check { 6.times { accounts.by_template("Conta #{_1}", 1) } }).to eq(6)
  end
end
