# frozen_string_literal: true

RSpec.describe "Counterparties", :db, type: :request do
  let(:db) { Hanami.app["db.gateway"].connection }
  let(:repo) { Hanami.app["repos.counterparty_repo"] }

  def names(body) = body.scan(%r{<span class="name">([^<]+)</span>}).flatten

  before do
    stub_const("Tally::Views::Counterparties::Index::PER_PAGE", 2)
    %w[ALFA BETA GAMA DELTA EPSILON].each { repo.upsert(name: "LOJA #{_1} EXEMPLO") }
    repo.upsert(name: "JOÃO  DA-SILVA EXEMPLO", document: "***.123.456-**", document_kind: "cpf_masked")
  end

  it "pages them in one order, keeping the search" do
    seen = (1..3).flat_map do |page|
      get "/counterparties", page: page.to_s
      expect(last_response.body).to include("6 counterparties", "Page #{page} of 3")
      names(last_response.body).tap { expect(_1.size).to eq(2) }
    end
    expect(seen.uniq.size).to eq(6)

    get "/counterparties", q: "loja", page: "2"
    expect(last_response.body).to include("5 counterparties", "Page 2 of 3")
    expect(last_response.body).to include(%(href="/counterparties?q=loja&amp;page=3">Next))
    expect(last_response.body).to include(%(href="/counterparties?q=loja&amp;page=1">))

    get "/counterparties", page: "99"
    expect(last_response.body).to include("Page 3 of 3")
  end

  it "finds a name without its accents, case or punctuation" do
    ["joao da silva", "João", "DA SILVA"].each do |query|
      get "/counterparties", q: query
      expect(names(last_response.body)).to eq(["JOÃO  DA-SILVA EXEMPLO"])
    end

    get "/counterparties", q: "100%_x"
    expect(last_response.body).to include("No one&#39;s name contains “100%_x”.")
  end

  it "comes back to the same search and page after \"This is me\"" do
    me = db[:counterparties].where(document: "***.123.456-**").get(:id)

    post "/counterparties/#{me}/self", is_self: "1", q: "x" * 101, page: "1"
    expect(last_response.headers["Location"]).to end_with("/counterparties?q=#{"x" * 100}&page=1")
    get "/counterparties", q: "  zzz "
    expect(last_response.body).to include("No one&#39;s name contains “zzz”.")
    get "/counterparties", q: "#{"x" * 100}y"
    expect(last_response.body).to include("No one&#39;s name contains “#{"x" * 100}”.")

    post "/counterparties/#{me}/self", is_self: "1", q: " joão ", page: "1"
    expect(last_response.headers["Location"]).to end_with("/counterparties?q=jo%C3%A3o&page=1")
    follow_redirect!
    expect(last_response.body).to include("JOÃO  DA-SILVA EXEMPLO</span> (you)")
  end
end
