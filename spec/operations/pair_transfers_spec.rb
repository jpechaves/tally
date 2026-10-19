# frozen_string_literal: true

RSpec.describe "Pairing transfers", :db do
  let(:db) { Hanami.app["db.gateway"].connection }
  let(:pair) { Hanami.app["operations.pair_transfers"] }

  def account(name, currency: "BRL", mirror: 0)
    db[:accounts].insert(name:, kind: "checking", currency:, mirror_transfers: mirror)
  end

  def leg(account_id, cents, to:, on: "2026-09-10", **attributes)
    @leg = (@leg || 0) + 1
    db[:transactions].insert(account_id:, occurred_on: on, amount_cents: cents, kind: "transfer", counter_account_id: to,
      description: "Transferência", raw_description: "Transferência", external_id: "leg-#{@leg}", **attributes)
  end

  def transfer_of(id) = db[:transactions].where(id:).get(:transfer_id)

  let(:checking) { account("Conta Exemplo") }
  let(:card) { account("Cartão Exemplo") }

  it "pairs opposite amounts between two imported accounts, and splits them when one changes" do
    paid = leg(checking, -50_000, to: card, on: "2026-09-10")
    received = leg(card, 50_000, to: checking, on: "2026-09-12")

    expect(pair.().value!).to eq(1)
    expect(transfer_of(paid)).to eq(transfer_of(received)).and be_truthy
    expect(db[:transfers].get(:occurred_on)).to eq("2026-09-10")

    db[:transactions].where(id: received).update(amount_cents: 50_100)
    expect(pair.(touched_ids: [paid]).value!).to eq(0)
    expect([transfer_of(paid), transfer_of(received)]).to eq([nil, nil])
    expect(db[:transfers].count).to eq(0)
  end

  it "keeps a pair between currencies while the amounts still match at the printed rate" do
    dollars = account("Conta Dólar", currency: "USD")
    reais = leg(checking, -100_000, to: dollars)
    top_up = leg(dollars, 17_874, to: checking, exchange_currency: "BRL", exchange_rate: "5.405405")

    expect(pair.().value!).to eq(1)
    transfer = transfer_of(top_up)
    expect(pair.(touched_ids: [reais, top_up]).value!).to eq(0)
    expect(transfer_of(reais)).to eq(transfer)

    db[:transactions].where(id: reais).update(amount_cents: -200_000)
    pair.(touched_ids: [reais])
    expect([transfer_of(reais), transfer_of(top_up)]).to eq([nil, nil])
  end

  it "writes a mirror row for an account without statements, reusing the one it wrote before" do
    savings = account("Poupança Exemplo", mirror: 1)
    saved = leg(checking, -30_000, to: savings, on: "2026-09-05")

    expect(pair.().value!).to eq(1)
    mirror = db[:transactions].where(account_id: savings).first
    expect(mirror).to include(amount_cents: 30_000, counter_account_id: checking, external_id: "mirror:#{saved}",
      transfer_id: transfer_of(saved))

    # Lose the link but not the mirror row: pairing again links the same row, updated.
    db[:transactions].update(transfer_id: nil)
    db[:transfers].delete
    db[:transactions].where(id: saved).update(amount_cents: -35_000)
    expect(pair.().value!).to eq(1)
    expect(db[:transactions].where(account_id: savings).select_map([:id, :amount_cents])).to eq([[mirror[:id], 35_000]])
    expect(transfer_of(mirror[:id])).to eq(transfer_of(saved))
  end
end
