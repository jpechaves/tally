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

  it "counts spending up to today, and leaves out what an adjustment says counts as nothing" do
    allow(Date).to receive(:today).and_return(Date.new(2026, 9, 10))
    insert("Hoje", -1_000)
    insert("Amanhã", -1_000, on: "2026-09-11")
    insert("Um centavo", 1)
    canceled = insert("Cancelada", -3_000)
    db[:transaction_adjustments].insert(transaction_id: canceled, kind: "canceled")
    descriptions = ->(kind) { repo.list(Tally::TransactionFilter.new(kind:)).map { _1[:description] } }

    expect(descriptions.call("spending")).to eq(["Hoje"])
    expect(descriptions.call("income")).to eq(["Um centavo"])
    expect(descriptions.call(nil)).to eq(["Amanhã", "Cancelada", "Um centavo", "Hoje"])
    expect(repo.to_review.map { _1[:description] }).to contain_exactly("Hoje", "Amanhã", "Um centavo")
  end

  it "offers money that came in, up to the purchase's amount, from a week before it to four months after, nearest first" do
    purchase = insert("Compra", -10_000)
    insert("Antes", 1_000, on: "2026-09-03")
    insert("Cedo demais", 1_000, on: "2026-09-02")
    insert("Depois", 1_000, on: "2026-12-20")
    insert("Tarde demais", 1_000, on: "2027-01-09")
    insert("Igual", 10_000, on: "2026-09-12")
    insert("Maior", 10_001, on: "2026-09-11")
    insert("Centavo", 1, on: "2026-09-20")

    candidates = repo.refund_candidates(repo.list(id: purchase).first)
    expect(candidates.map { _1[:description] }).to eq(%w[Igual Antes Centavo Depois])
    20.times { |i| insert("Mais #{i}", 100, on: "2026-10-#{10 + i}") }
    expect(repo.refund_candidates(repo.list(id: purchase).first).size).to eq(20)
  end
end
