# frozen_string_literal: true

RSpec.describe "SQLite settings", :db do
  let(:db) { Hanami.app["db.gateway"].connection }

  def pragma(name) = db.fetch("PRAGMA #{name}").single_value

  it "turns on the reliability pragmas for every connection" do
    expect(pragma("foreign_keys")).to eq(1)
    expect(pragma("journal_mode")).to eq("wal")
    expect(pragma("synchronous")).to eq(2) # FULL
    expect(pragma("busy_timeout")).to eq(5_000)
  end

  it "runs a SQLite new enough for STRICT tables (3.37+)" do
    version = Gem::Version.new(db.fetch("SELECT sqlite_version()").single_value)

    expect(version).to be >= Gem::Version.new("3.37")
  end

  describe "accounts table" do
    let(:accounts) { db[:accounts] }

    it "is STRICT, so a fractional amount can't be stored in a cents column" do
      expect {
        accounts.insert(name: "Conta Exemplo", kind: "checking", opening_balance_cents: 12.5)
      }.to raise_error(Sequel::DatabaseError, /cannot store REAL value in INTEGER column/)
    end

    it "stores whole cents and defaults the currency to BRL" do
      id = accounts.insert(name: "Conta Exemplo", kind: "checking", opening_balance_cents: 123_456)
      row = accounts.where(id: id).first

      expect(row[:opening_balance_cents]).to eq(123_456)
      expect(row[:currency]).to eq("BRL")
      expect(row[:created_at]).to match(/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z\z/)
    end

    it "only accepts known account kinds" do
      expect {
        accounts.insert(name: "Conta Exemplo", kind: "crypto")
      }.to raise_error(Sequel::CheckConstraintViolation)
    end

    it "keeps account names unique" do
      accounts.insert(name: "Conta Exemplo", kind: "checking")

      expect {
        accounts.insert(name: "Conta Exemplo", kind: "credit_card")
      }.to raise_error(Sequel::UniqueConstraintViolation)
    end
  end
end
