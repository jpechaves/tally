# frozen_string_literal: true

RSpec.describe "Account and category totals", :db do
  let(:db) { Hanami.app["db.gateway"].connection }

  it "shows an account with no rows at its opening balance" do
    db[:accounts].insert(name: "Conta Exemplo", kind: "checking", opening_balance_cents: 12_345)

    expect(Hanami.app["repos.account_repo"].with_balances.map { _1.slice(:rows, :balance_cents) })
      .to eq([{rows: 0, balance_cents: 12_345}])
  end

  it "adds an account's rows to its opening balance" do
    account = db[:accounts].insert(name: "Conta Exemplo", kind: "checking", opening_balance_cents: 12_345)
    db[:transactions].insert(account_id: account, occurred_on: "2026-09-10", amount_cents: -2_345, kind: "purchase",
      description: "Loja", raw_description: "Loja", external_id: "loja")

    expect(Hanami.app["repos.account_repo"].with_balances.map { _1.slice(:rows, :balance_cents) })
      .to eq([{rows: 1, balance_cents: 10_000}])
  end

  it "anchors an account's balance on the newest balance check" do
    account = db[:accounts].insert(name: "Conta Exemplo", kind: "checking", opening_balance_cents: 12_345)
    %w[2026-09-10 2026-10-20].each do |day|
      db[:transactions].insert(account_id: account, occurred_on: day, amount_cents: -2_345, kind: "purchase",
        description: "Loja", raw_description: "Loja", external_id: "loja-#{day}")
    end
    checks = Hanami.app["repos.balance_check_repo"]
    checks.add(account_id: account, checked_on: "2026-10-01", balance_cents: 216_102)
    checks.add(account_id: account, checked_on: "2026-10-01", balance_cents: 216_000)

    entry = Hanami.app["repos.account_repo"].with_balances(checks.by_account).first
    expect(entry.slice(:rows, :balance_cents)).to eq(rows: 2, balance_cents: 213_655)
    expect(entry[:checks].map(&:balance_cents)).to eq([216_000])
  end

  it "knows when there are no categories, and counts nothing for one no row uses" do
    categories = Hanami.app["repos.category_repo"]
    expect(categories).to be_empty

    db[:categories].insert(name: "Feira", kind: "expense")
    expect(categories).not_to be_empty
    expect(categories.tree.map { _1.slice(:name, :rows, :total_cents) }).to eq([{name: "Feira", rows: 0, total_cents: 0}])
  end

  it "lists each parent before its children, labels a child with its parent, and leaves archived ones out" do
    casa = db[:categories].insert(name: "Casa", kind: "expense")
    db[:categories].insert(name: "Água", kind: "expense", parent_id: casa)
    db[:categories].insert(name: "Dados", kind: "expense")
    db[:categories].insert(name: "Antiga", kind: "expense", archived_at: "2026-09-01T00:00:00Z")
    categories = Hanami.app["repos.category_repo"]

    expect(categories.tree.map { _1[:label] }).to eq(["Casa", "Casa › Água", "Dados"])
    expect(categories.tree(include_archived: true).map { _1[:label] }).to eq(["Antiga", "Casa", "Casa › Água", "Dados"])
  end

  it "totals nothing for a counterparty with no rows" do
    Hanami.app["repos.counterparty_repo"].upsert(name: "LOJA EXEMPLO")

    expect(Hanami.app["repos.counterparty_repo"].with_totals.map { _1.slice(:name, :rows, :total_cents) })
      .to eq([{name: "LOJA EXEMPLO", rows: 0, total_cents: 0}])
  end
end
