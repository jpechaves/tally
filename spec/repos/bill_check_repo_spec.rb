# frozen_string_literal: true

RSpec.describe Tally::Repos::BillCheckRepo, :db do
  subject(:checks) { Hanami.app["repos.bill_check_repo"].all }

  let(:db) { Hanami.app["db.gateway"].connection }
  let(:import_id) do
    db[:imports].insert(source: "test", file_name: "test.csv", file_sha256: "0" * 64, file_size: 1, status: "applied")
  end
  let(:card) { db[:accounts].insert(name: "Nubank cartão", kind: "credit_card") }
  let(:conta) { db[:accounts].insert(name: "Nubank conta", kind: "checking") }

  def bill(due_on, total)
    db[:card_statements].insert(account_id: card, due_on:, total_cents: (total * 100).round, import_id:)
  end

  def payment(occurred_on, amount)
    @payment = (@payment || 0) + 1
    db[:transactions].insert(
      account_id: conta, occurred_on:, amount_cents: -(amount * 100).round, kind: "transfer",
      description: "Pagamento de fatura", raw_description: "Pagamento de fatura", external_id: "p#{@payment}"
    )
  end

  def check(due_on) = checks.find { _1[:due_on] == due_on }

  before { allow(Date).to receive(:today).and_return(Date.new(2026, 10, 18)) }

  it "counts a bill paid in parts, one while it was still open, as paid in full" do
    bill("2026-03-09", 1_000)
    bill("2026-04-09", 5_000)
    payment("2026-03-09", 1_000)
    payment("2026-03-15", 2_000)
    payment("2026-04-08", 3_000)

    expect(check("2026-03-09")).to include(status: "ok", paid_cents: 100_000)
    expect(check("2026-04-09")).to include(status: "ok", paid_cents: 500_000, difference_cents: 0)
  end

  it "counts money paid after a bill is settled toward the next bill" do
    bill("2026-05-09", 4_000)
    bill("2026-06-09", 2_500)
    payment("2026-05-09", 1_000) # a prepayment toward June, recorded first
    payment("2026-05-09", 4_000)
    payment("2026-06-09", 1_500)

    expect(check("2026-05-09")).to include(status: "ok", paid_cents: 400_000)
    expect(check("2026-06-09")).to include(status: "ok", paid_cents: 250_000)
  end

  it "leaves out payments of a bill that is not imported" do
    bill("2026-05-09", 4_000)
    payment("2026-04-09", 900)
    payment("2026-05-09", 4_000)

    expect(check("2026-05-09")).to include(status: "ok", paid_cents: 400_000)
  end

  it "still warns about a one-centavo gap" do
    bill("2026-07-09", 1_765.75)
    payment("2026-07-09", 1_765.74)

    expect(check("2026-07-09")).to include(status: "warning", difference_cents: 1)
  end

  it "counts a payment a few days late toward its own bill, and shows money paid too much" do
    bill("2026-07-09", 1_000)
    bill("2026-08-09", 1_000)
    payment("2026-07-11", 1_000)
    payment("2026-08-10", 1_500)

    expect(check("2026-07-09")).to include(status: "ok", paid_cents: 100_000)
    expect(check("2026-08-09")).to include(status: "warning", paid_cents: 150_000, difference_cents: 50_000)
  end

  it "keeps a bill's shortfall on that bill, not on the later ones" do
    bill("2026-01-09", 1_000)
    bill("2026-02-09", 500)
    bill("2026-11-09", 3_000)
    payment("2026-01-07", 900)
    payment("2026-02-09", 500)
    payment("2026-10-09", 700)

    expect(check("2026-01-09")).to include(status: "warning", paid_cents: 90_000, difference_cents: 10_000)
    expect(check("2026-02-09")).to include(status: "ok", paid_cents: 50_000)
    expect(check("2026-11-09")).to include(status: "open", paid_cents: 70_000)
  end

  it "shows a bill not due yet as open, even with nothing paid" do
    bill("2026-10-09", 1_000)
    bill("2026-11-09", 2_000)
    payment("2026-10-09", 1_000)

    expect(check("2026-11-09")).to include(status: "open", paid_cents: nil)
  end

  it "warns about a bill due today that isn't paid in full" do
    bill("2026-10-18", 1_000)
    payment("2026-10-15", 500)

    expect(check("2026-10-18")).to include(status: "warning", difference_cents: 50_000)
  end

  it "still warns about a bill not due yet that was paid too much" do
    bill("2026-11-09", 1_000)
    payment("2026-10-20", 1_200)

    expect(check("2026-11-09")).to include(status: "warning", difference_cents: 20_000)
  end

  it "says unknown for a bill nothing paid yet" do
    bill("2026-07-09", 1_000)
    bill("2026-08-09", 1_000)
    payment("2026-07-09", 1_000)

    expect(check("2026-08-09")).to include(status: "unknown", paid_cents: nil)
  end

  it "leaves out a payment made after the last bill was due" do
    bill("2026-07-09", 1_000)
    payment("2026-07-09", 1_000)
    payment("2026-07-20", 500)

    expect(check("2026-07-09")).to include(status: "ok", paid_cents: 100_000)
  end

  it "says unknown for every bill when there's no account statement" do
    bill("2026-07-09", 1_000)

    expect(checks).to eq([{account: "Nubank cartão", due_on: "2026-07-09", total_cents: 100_000, paid_by: "Nubank conta",
      paid_cents: nil, status: "unknown", difference_cents: nil}])
  end

  it "chains an Itaú bill to the payment the next bill prints" do
    itau = db[:accounts].insert(name: "Itaú cartão", kind: "credit_card")
    statement = ->(due_on, total, payments) do
      db[:card_statements].insert(account_id: itau, due_on:, total_cents: total, payments_cents: payments, import_id:)
    end
    statement.("2026-08-09", 120_000, 90_000)
    statement.("2026-09-09", 80_000, 120_000)
    statement.("2026-10-09", 50_000, 79_000)

    expect(checks.map { _1.values_at(:account, :due_on, :paid_by, :paid_cents, :status, :difference_cents) }).to eq([
      ["Itaú cartão", "2026-08-09", nil, 120_000, "ok", 0],
      ["Itaú cartão", "2026-09-09", nil, 79_000, "warning", 1_000],
      ["Itaú cartão", "2026-10-09", nil, nil, "unknown", nil]
    ])
  end
end
