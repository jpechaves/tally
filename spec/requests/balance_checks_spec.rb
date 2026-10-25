# frozen_string_literal: true

require "rack/test"

RSpec.describe "Balance checks", :db, type: :request do
  let(:db) { Hanami.app["db.gateway"].connection }
  let(:conta) { db[:accounts].insert(name: "Nubank conta", kind: "checking") }

  def row(occurred_on, cents)
    db[:transactions].insert(account_id: conta, occurred_on:, amount_cents: cents, kind: "purchase", description: "Loja",
      raw_description: "Loja", external_id: "loja-#{occurred_on}")
  end

  before { allow(Date).to receive(:today).and_return(Date.new(2026, 10, 25)) }

  it "anchors the balance on what the bank showed, flags rows that don't add up, and deletes a check" do
    row("2026-10-10", -50_00)
    row("2026-10-20", -10_00)
    get "/accounts"
    expect(last_response.body).to include("-R$ 60.00", %(value="2026-10-25"), "Check balances")

    post "/accounts/balance-checks", account_id: conta.to_s, checked_on: "2026-10-15", balance: "2,161.02"
    expect(last_response.location).to end_with("/accounts#balances")
    get "/accounts"
    expect(last_response.body).to include("R$ 2,151.02", "checked on Oct 15, 2026")

    post "/accounts/balance-checks", account_id: conta.to_s, checked_on: "2026-10-25", balance: "2,141.02"
    get "/accounts"
    expect(last_response.body).to include("R$ 2,141.02", "-R$ 10.00 off since the check before", "checked on Oct 25, 2026")

    post "/balance-checks/#{db[:balance_checks].where(checked_on: "2026-10-25").get(:id)}/delete"
    expect(last_response.location).to end_with("/accounts#balances")
    expect(db[:balance_checks].count).to eq(1)
  end

  it "refuses a check without a known account, a day or an amount" do
    post "/accounts/balance-checks", account_id: "999", checked_on: "2026-10-15", balance: "1.00"
    expect(last_response.status).to eq(422)
    post "/accounts/balance-checks", account_id: conta.to_s, checked_on: "2026-13-45", balance: "1.00"
    expect(last_response.status).to eq(422)
    post "/accounts/balance-checks", account_id: conta.to_s, checked_on: "2026-10-15", balance: "abc"
    expect(last_response.body).to include("A balance check needs an account")
    expect(db[:balance_checks].count).to eq(0)
  end
end
