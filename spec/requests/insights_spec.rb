# frozen_string_literal: true

require "fileutils"

RSpec.describe "Report, cuts and installments", :db, type: :request do
  let(:db) { Hanami.app["db.gateway"].connection }

  before do
    %w[NU_12345678_01JUL2026_31JUL2026.csv Nubank_2026-07-09.csv Nubank_2026-08-09.csv itau_2026-10.pdf
      itau_2027-01_tight.pdf].each do |name|
      Hanami.app["operations.import_statement"].(file_name: name, content: fixture(name))
    end
  end

  after { FileUtils.rm_rf(Hanami.app.root.join(Hanami.app["settings"].import_storage_dir)) }

  it "says so when nothing is imported" do
    db[:transactions].delete
    get "/report"

    expect(last_response.body).to include("Nothing imported yet.")
  end

  it "shows a month's income, spending, categories and installments" do
    get "/report", month: "2026-07"

    expect(last_response.status).to eq(200)
    body = last_response.body
    expect(body).to include("Income<strong>R$ 8,920.00</strong>", "Averages over Jun 2026.")
    expect(body).not_to match(/<t[rd][a-z]/)
    expect(body).to include(%(aria-label="Income and spending by month"), %(<span class="pct">))
    expect(body).to include(">Transfers (Pix)</a></td>", ">Food delivery</a></td>", ">No category</a></td>")
    expect(body).to include("R$ 1,559.30 of this month&#39;s spending, 3 installments.")
    expect(body).to match(%r{>Hotel Exemplo</a> .*?</td>\s*<td>2/6</td>\s*<td>Nov 2026</td>}m)
    expect(body).not_to include("Pagamento de fatura")
  end

  it "opens on the latest month that is over, since the current one is only partly imported" do
    allow(Date).to receive(:today).and_return(Date.new(2026, 10, 15))
    get "/report"
    expect(last_response.body).to include(%(<option value="2026-09" selected>))
    get "/cuts"
    expect(last_response.body).to include(%(<option value="2026-09" selected>))

    allow(Date).to receive(:today).and_return(Date.new(2026, 1, 15))
    get "/report"
    expect(last_response.body).to include(%(<option value="2027-01" selected>))
  end

  it "suggests cuts and lets you dismiss and bring them back" do
    get "/cuts", month: "2026-09"
    expect(last_response.body).to include("Fees, interest and financing: R$ 52.50", "Possible duplicate charge")

    parking = db[:counterparties].where(name: "ESTACIONAMENTO EXEMPLO").get(:id)
    key = "duplicate:counterparty:#{parking}:-1400"
    expect(last_response.body).to include(%(value="#{key}"))
    post "/cuts/dismiss", key:, title: "ESTACIONAMENTO EXEMPLO: R$ 14.00 charged 2 times", month: "2026-09"
    expect(last_response.headers["Location"]).to end_with("/cuts?month=2026-09")

    follow_redirect!
    expect(last_response.body).not_to include(%(value="#{key}"))
    expect(last_response.body).to include("Dismissed", "ESTACIONAMENTO EXEMPLO: R$ 14.00 charged 2 times")

    post "/cuts/#{db[:dismissed_suggestions].get(:id)}/restore", month: "2026-09"
    expect(last_response.headers["Location"]).to end_with("/cuts?month=2026-09")
    follow_redirect!
    expect(last_response.body).to include(%(value="#{key}"))
  end

  it "lists installments committed from their first month on, next to what the bank printed" do
    allow(Date).to receive(:today).and_return(Date.new(2027, 1, 15))
    get "/installments"

    body = last_response.body
    expect(body).to include("R$ 840.00 already committed to card bills from Feb 2027 on, from 1 purchase.", "Left from Feb 2027")
    expect(body).not_to include("Left from Jan 2027")
    expect(body).to include(%(aria-label="Installments committed per month"), "<title>Feb 2027 · Committed: R$ 120.00</title>")
    expect(body).to match(%r{<td>Feb 2027</td>\s*<td class="num">R\$ 120\.00</td>})
    expect(body).to match(%r{<td>Itaú cartão</td>\s*<td>Jan 9, 2027</td>\s*<td class="num">R\$ 120\.00</td>\s*<td class="num">R\$ 840\.00</td>})
  end
end
