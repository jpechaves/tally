# frozen_string_literal: true

RSpec.describe "Account and category totals", :db do
  let(:db) { Hanami.app["db.gateway"].connection }

  it "shows an account with no rows at its opening balance" do
    db[:accounts].insert(name: "Conta Exemplo", kind: "checking", opening_balance_cents: 12_345)

    expect(Hanami.app["repos.account_repo"].with_balances.map { _1.slice(:rows, :balance_cents) })
      .to eq([{rows: 0, balance_cents: 12_345}])
  end

  it "knows when there are no categories, and counts nothing for one no row uses" do
    categories = Hanami.app["repos.category_repo"]
    expect(categories).to be_empty

    db[:categories].insert(name: "Feira", kind: "expense")
    expect(categories).not_to be_empty
    expect(categories.tree.map { _1.slice(:name, :rows, :total_cents) }).to eq([{name: "Feira", rows: 0, total_cents: 0}])
  end
end
