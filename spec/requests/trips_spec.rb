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
    post "/trips", {name: "Chile, mar/2026", starts_on: "2026-03-10", ends_on: "2026-03-18", all_accounts: "1"}.merge(params)
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

  it "checks cards and accounts in another currency by default, grouped by person, and asks for at least one" do
    db[:people].where(id: Hanami.app["repos.person_repo"].first.id).update(name: "Maria Souza")
    db[:accounts].where(id: itau).update(person_id: db[:people].insert(name: "Bruno Exemplo"))

    get "/trips"
    body = last_response.body
    expect(body).to include(%(<input type="checkbox" name="account_ids[]" value="#{nubank}" checked>),
      %(<input type="checkbox" name="account_ids[]" value="#{global}" checked>),
      %(<input type="checkbox" name="account_ids[]" value="#{conta}">), %(<input type="checkbox" name="all_accounts" value="1">),
      "<legend>Maria Souza</legend>", "<legend>Bruno Exemplo</legend>")

    create_trip(all_accounts: nil)
    expect(last_response.status).to eq(422)
    expect(last_response.body).to include("Pick the accounts")
    expect(create_trip[:id]).to be_positive
    expect(db[:trip_accounts].count).to eq(0)
  end

  it "edits a trip's name, dates and accounts, keeping the rows chosen by hand" do
    trip = create_trip
    post "/trips/rows", trip_id: trip[:id], transaction_id: flight, included: "1"
    get "/trips/#{trip[:id]}"
    expect(last_response.body).to include(%(action="/trips/#{trip[:id]}"), %(value="Chile, mar/2026"), %(<input type="checkbox" name="all_accounts" value="1" checked>),
      %(<input type="checkbox" name="account_ids[]" value="#{nubank}">))

    post "/trips/#{trip[:id]}", name: "Chile", starts_on: "2026-03-11", ends_on: "2026-03-12", account_ids: [nubank.to_s, "999"]
    expect(last_response.location).to end_with("/trips/#{trip[:id]}")
    expect(db[:trips].where(id: trip[:id]).get(%i[name starts_on ends_on])).to eq(["Chile", "2026-03-11", "2026-03-12"])
    expect(db[:trip_accounts].select_map(:account_id)).to eq([nubank])
    expect(db[:trip_rows].count).to eq(1)

    get "/trips/#{trip[:id]}"
    expect(last_response.body).to include("Nubank cartão", "LATAM AIR", %(<input type="checkbox" name="account_ids[]" value="#{nubank}" checked>),
      %(<input type="checkbox" name="account_ids[]" value="#{global}">))
    expect(last_response.body).not_to include("HOTEL EXEMPLO")

    post "/trips/#{trip[:id]}", name: "Chile", starts_on: "2026-03-11", ends_on: "2026-03-12"
    expect(last_response.status).to eq(422)
    post "/trips/999", name: "Chile", starts_on: "2026-03-11", ends_on: "2026-03-12", all_accounts: "1"
    expect(last_response.status).to eq(404)
  end

  it "suggests purchases from before the trip, from the travel list kept on the trips page" do
    trip = create_trip(account_ids: [nubank.to_s], all_accounts: nil)
    get "/trips/#{trip[:id]}"
    expect(last_response.body).not_to include("Suggestions")

    post "/trips/words", word: " LATAM "
    expect(last_response.location).to end_with("/trips")
    post "/trips/words", word: "látam"
    expect(db[:travel_words].select_map(:word)).to eq(["LATAM"])
    post "/trips/words", word: " "
    expect(last_response.status).to eq(422)
    get "/trips"
    expect(last_response.body).to include("Travel words", "LATAM", %(action="/trips/words/#{db[:travel_words].get(:id)}/delete"))

    get "/trips/#{trip[:id]}"
    body = last_response.body
    expect(body).to include("Suggestions", "LATAM AIR", %(<button type="submit" name="included" value="1">Add</button>))
    expect(body.scan("LATAM AIR").size).to eq(1)

    post "/trips/rows", trip_id: trip[:id], transaction_id: flight, included: "0"
    get "/trips/#{trip[:id]}"
    expect(last_response.body).not_to include("Suggestions")

    post "/trips/words/#{db[:travel_words].get(:id)}/delete"
    expect(db[:travel_words].count).to eq(0)
    post "/trips/words/999/delete"
    expect(last_response.status).to eq(404)
  end

  it "keeps to the trip's accounts, takes rows out and puts them back" do
    trip = create_trip(account_ids: [nubank.to_s], all_accounts: nil)
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

  it "maps the places of each trip, and lists the ones not on the map" do
    row(itau, "2026-03-13", 4_000, "CAFE EXEMPLO", location: "SANTIAGO")
    row(itau, "2026-03-14", 2_000, "LOJA EXEMPLO", location: "VILA EXEMPLO")
    row(global, "2026-03-15", 3_000, "Loja Exemplo Buenos Aires")
    trip = create_trip

    get "/trips/#{trip[:id]}"
    body = last_response.body
    expect(body).to include(%(<svg class="map"), "<title>Santiago</title>", "<title>Buenos Aires</title>", "Not on the map: HOTEL EXEMPLO, VILA EXEMPLO")

    post "/trips", name: "Lisboa, jan/2026", starts_on: "2026-01-01", ends_on: "2026-01-05", all_accounts: "1"
    get "/trips"
    expect(last_response.body).to include(%(<svg class="map"), "<title>Santiago</title>", "Not on the map: HOTEL EXEMPLO, VILA EXEMPLO")

    get "/trips/#{db[:trips].order(:id).last[:id]}"
    expect(last_response.body).not_to include(%(<svg class="map"), "Not on the map")

    get "/assets/world.svg"
    expect(last_response.headers).to include("Content-Type" => "image/svg+xml; charset=utf-8", "Cache-Control" => "max-age=604800")
    expect(last_response.body).to include(%(<path id="world"))
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
