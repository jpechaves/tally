# frozen_string_literal: true

RSpec.describe "Subscriptions", :db, type: :request do
  let(:db) { Hanami.app["db.gateway"].connection }
  let(:card) { db[:accounts].insert(name: "Nubank cartão", kind: "credit_card") }
  let(:conta) { db[:accounts].insert(name: "Nubank conta", kind: "checking") }

  def party(name) = db[:counterparties].insert(name:, match_key: "|#{name.upcase}")

  def charge(account_id, occurred_on, cents, description, counterparty_id: nil)
    db[:transactions].insert(account_id:, occurred_on:, amount_cents: -cents, kind: "purchase", description:,
      raw_description: description, external_id: "#{account_id}-#{occurred_on}-#{description}", counterparty_id:)
  end

  before do
    allow(Date).to receive(:today).and_return(Date.new(2026, 10, 15))
    streamflix = party("StreamFlix")
    gym = party("Academia Forte")
    %w[06 07 08].each { charge(card, "2026-#{_1}-05", 3_990, "STREAMFLIX", counterparty_id: streamflix) }
    charge(card, "2026-09-05", 4_490, "STREAMFLIX", counterparty_id: streamflix)
    %w[07 08].each { charge(conta, "2026-#{_1}-10", 9_900, "Academia Forte", counterparty_id: gym) }
    charge(card, "2026-09-10", 9_900, "ACADEMIA FORTE", counterparty_id: gym)
    %w[04 05 06 07].each { charge(card, "2026-#{_1}-20", 1_990, "MUSICAPP") }
  end

  it "lists them with monthly and yearly cost, flags, and links to their rows" do
    get "/subscriptions"

    body = last_response.body
    expect(last_response).to be_ok
    expect(body).to include("R$ 143.90 a month", "R$ 1,726.80 a year")
    expect(body).to include("StreamFlix", "up R$ 5.00", "Academia Forte", "Nubank conta, Nubank cartão", "Jul 2026")
    expect(body).to include("MUSICAPP", %(<span class="badge">stopped</span>))
    expect(body).to include(%(href="/transactions?kind=spending&amp;payee=counterparty%3A#{db[:counterparties].where(name: "StreamFlix").get(:id)}&amp;back=%2Fsubscriptions"))
    expect(body).to include(%(href="/home-bills?payee=counterparty%3A#{db[:counterparties].where(name: "StreamFlix").get(:id)}&amp;name=StreamFlix&amp;amount=44.90&amp;day=5#new">Track as home bill))

    get "/cuts"
    expect(last_response.body).to include(%(href="/subscriptions"))
  end

  it "keeps a dismissed one out and lists one marked by hand, until undone" do
    post "/subscriptions/marks", key: "description:musicapp", kind: "dismissed", title: "MUSICAPP"
    expect(last_response.location).to end_with("/subscriptions")
    get "/subscriptions"
    expect(last_response.body).not_to include(%(<span class="badge">stopped</span>))
    expect(last_response.body).to include("Not subscriptions", "MUSICAPP")

    insurance = party("Seguro Exemplo")
    charge(card, "2026-09-12", 120_000, "SEGURO EXEMPLO", counterparty_id: insurance)
    get "/counterparties/#{insurance}"
    expect(last_response.body).to include(%(name="key" value="counterparty:#{insurance}"))
    post "/subscriptions/marks", key: "counterparty:#{insurance}", kind: "marked", title: "Seguro Exemplo",
      back: "/counterparties/#{insurance}"
    expect(last_response.location).to end_with("/counterparties/#{insurance}")
    get "/subscriptions"
    expect(last_response.body).to include("R$ 1,343.90 a month", "Seguro Exemplo", "marked by hand")

    db[:subscription_marks].select_map(:id).each { post "/subscriptions/marks/#{_1}/remove" }
    get "/subscriptions"
    expect(last_response.body).to include("R$ 143.90 a month", %(<span class="badge">stopped</span>))
    expect(db[:subscription_marks].count).to eq(0)
  end

  it "refuses a mark without a payee or kind, and undoing one that doesn't exist" do
    post "/subscriptions/marks", key: "", kind: "marked"
    expect(last_response.status).to eq(422)
    post "/subscriptions/marks", key: "description:x", kind: "other"
    expect(last_response.status).to eq(422)
    post "/subscriptions/marks/999/remove"
    expect(last_response.status).to eq(404)
  end

  it "says so when nothing is imported" do
    db[:transactions].delete
    get "/subscriptions"
    expect(last_response.body).to include("Nothing imported yet")
  end
end
