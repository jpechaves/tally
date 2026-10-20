# frozen_string_literal: true

RSpec.describe "Trips", :db, type: :request do
  let(:db) { Hanami.app["db.gateway"].connection }
  let(:nubank) { account("Nubank cartão") }
  let(:itau) { account("Itaú cartão") }
  let(:global) { account("Conta Global", currency: "USD") }
  let(:conta) { account("Nubank conta", kind: "checking") }

  def account(name, kind: "credit_card", currency: "BRL") = db[:accounts].insert(name:, kind:, currency:)

  def row(account_id, occurred_on, cents, description, kind: "purchase", **attributes)
    db[:transactions].insert(account_id:, occurred_on:, amount_cents: -cents, kind:, description:, raw_description: description,
      external_id: "#{account_id}-#{occurred_on}-#{description}-#{cents}", **attributes)
  end

  let!(:flight) do
    flight = {purchased_on: "2026-01-15", installment_total: 6}
    row(itau, "2026-01-20", 50_000, "LATAM AIR", installment_number: 1, **flight).tap do
      row(itau, "2026-02-20", 50_000, "LATAM AIR", installment_number: 2, **flight)
    end
  end
  let!(:car) { row(nubank, "2026-03-12", 90_000, "LOCADORA EXEMPLO") }

  before do
    allow(Date).to receive(:today).and_return(Date.new(2026, 4, 15))
    transfer = db[:transfers].insert(occurred_on: "2026-03-01")
    row(global, "2026-03-01", -100_000, "TOPUP EXEMPLO", kind: "transfer", transfer_id: transfer)
    row(conta, "2026-03-01", 520_000, "Conversão para Conta Global", kind: "transfer", transfer_id: transfer)
    row(global, "2026-03-11", 80_000, "HOTEL EXEMPLO")
    row(nubank, "2026-03-12", 3_915, "IOF de \"LOCADORA EXEMPLO\"", kind: "fee")
    row(nubank, "2026-03-25", 10_000, "MERCADO EXEMPLO")
  end

  def create_trip(**params)
    post "/trips", {name: "Chile, mar/2026", starts_on: "2026-03-10", ends_on: "2026-03-18"}.merge(params)
    db[:trips].order(:id).last
  end

  it "adds up a trip across cards, dollars and IOF, with rows added from before it" do
    trip = create_trip
    expect(last_response.location).to end_with("/trips/#{trip[:id]}")

    get "/transactions/#{flight}"
    expect(last_response.body).to include(%(<option value="#{trip[:id]}">Chile, mar/2026</option>))
    post "/trips/rows", trip_id: trip[:id], transaction_id: flight, included: "1", back: "/transactions/#{flight}"
    expect(last_response.location).to end_with("/transactions/#{flight}")

    get "/trips/#{trip[:id]}"
    body = last_response.body
    expect(body).to include("R$ 8,099.15", "US$ 800.00", "R$ 4,160.00", "IOF: R$ 39.15", "4 installments to come: R$ 2,000.00")
    expect(body).to include(%(href="/transactions?account=#{global}&amp;trip=#{trip[:id]}&amp;back=%2Ftrips%2F#{trip[:id]}"),
      %(href="/transactions?category=none&amp;trip=#{trip[:id]}&amp;back=%2Ftrips%2F#{trip[:id]}"))
    expect(body).not_to include("MERCADO EXEMPLO", "TOPUP EXEMPLO")

    get "/transactions", trip: trip[:id].to_s
    expect(last_response.body).to include("Trip: Chile, mar/2026", "LATAM AIR", "HOTEL EXEMPLO")
    expect(last_response.body).not_to include("MERCADO EXEMPLO")

    get "/trips"
    expect(last_response.body).to include("Chile, mar/2026", "R$ 8,099.15")
  end

  it "keeps to the trip's accounts, takes rows out and puts them back" do
    trip = create_trip(account_ids: [nubank.to_s])
    get "/trips/#{trip[:id]}"
    expect(last_response.body).to include("R$ 939.15")
    expect(last_response.body).not_to include("HOTEL EXEMPLO")

    post "/trips/rows", trip_id: trip[:id], transaction_id: car, included: "0"
    expect(last_response.location).to end_with("/trips/#{trip[:id]}")
    get "/trips/#{trip[:id]}"
    expect(last_response.body).to include("R$ 39.15", "Taken out", "LOCADORA EXEMPLO")

    post "/trips/rows", trip_id: trip[:id], transaction_id: car, included: ""
    expect(db[:trip_rows].count).to eq(0)
  end

  it "can hide trips from the monthly report" do
    create_trip
    get "/report", month: "2026-03"
    expect(last_response.body).to include("R$ 1,039.15", %(href="/report?month=2026-03&amp;trips=hide"))

    get "/report", month: "2026-03", trips: "hide"
    expect(last_response.body).to include("R$ 100.00", %(href="/report?month=2026-03"))
    expect(last_response.body).not_to include("R$ 1,039.15")
  end

  it "deletes a trip, and refuses bad dates, unknown trips and rows" do
    trip = create_trip
    post "/trips/#{trip[:id]}/delete"
    expect(last_response.location).to end_with("/trips")
    expect(db[:trips].count).to eq(0)

    create_trip(starts_on: "2026-03-18", ends_on: "2026-03-10")
    expect(last_response.status).to eq(422)
    create_trip(name: " ")
    expect(last_response.status).to eq(422)
    create_trip(ends_on: "2026-02-31")
    expect(last_response.status).to eq(422)

    get "/trips/999"
    expect(last_response.status).to eq(404)
    get "/transactions", trip: "999"
    expect(last_response.body).to include("Trip: 999", "No transactions match these filters.")
    post "/trips/999/delete"
    expect(last_response.status).to eq(404)
    post "/trips/rows", trip_id: 999, transaction_id: car, included: "1"
    expect(last_response.status).to eq(404)
    trip = create_trip
    post "/trips/rows", trip_id: trip[:id], transaction_id: 999_999, included: "1"
    expect(last_response.status).to eq(404)
  end
end
