# frozen_string_literal: true

RSpec.describe Tally::Repos::TransactionRepo, :db do
  subject(:repo) { Hanami.app["repos.transaction_repo"] }

  let(:db) { Hanami.app["db.gateway"].connection }
  let(:account) { db[:accounts].insert(name: "Conta Exemplo", kind: "checking") }

  def import = db[:imports].insert(source: "test", file_name: "test.csv", file_sha256: rand.to_s, file_size: 1, status: "applied")

  def insert(text, cents, on: "2026-09-10", kind: cents.negative? ? "purchase" : "income", **attributes)
    db[:transactions].insert(account_id: account, occurred_on: on, amount_cents: cents, kind:, description: text,
      raw_description: text, external_id: text, **attributes)
  end

  it "lists the rows an import found missing apart from the ones it read" do
    first = import
    later = import
    insert("Lida", -1_000, last_import_id: later)
    insert("Sumiu", -2_000, last_import_id: first, missing_since_import_id: later)

    expect(repo.list(import_id: later, missing: true).map { _1[:description] }).to eq(["Sumiu"])
    expect(repo.list(import_id: later).map { _1[:description] }).to eq(["Lida"])
  end

  it "offers money that came in from a week before a purchase to four months after it" do
    purchase = insert("Compra", -10_000)
    insert("Antes", 1_000, on: "2026-09-03")
    insert("Cedo demais", 1_000, on: "2026-09-02")
    insert("Depois", 1_000, on: "2026-12-20")
    insert("Tarde demais", 1_000, on: "2027-01-09")

    candidates = repo.refund_candidates(repo.list(id: purchase).first)
    expect(candidates.map { _1[:description] }).to contain_exactly("Antes", "Depois")
  end
end
