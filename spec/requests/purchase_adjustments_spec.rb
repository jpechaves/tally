# frozen_string_literal: true

require "fileutils"

RSpec.describe "Adjusting every installment of a purchase", :db, type: :request do
  let(:db) { Hanami.app["db.gateway"].connection }
  let(:import) { Hanami.app["operations.import_statement"] }

  before do
    allow(Date).to receive(:today).and_return(Date.new(2026, 10, 15))
    %w[Nubank_2026-07-09.csv Nubank_2026-08-09.csv].each { import.call(file_name: _1, content: fixture(_1)) }
  end

  after { FileUtils.rm_rf(Hanami.app.root.join(Hanami.app["settings"].import_storage_dir)) }

  def hotel = db[:transactions].where(description: "Hotel Exemplo").order(:installment_number).all

  def counted = Hanami.app["repos.insight_repo"].rows(from: "2026-01", to: "2026-12").select { _1[:description] == "Hotel Exemplo" }.map { _1[:amount_cents] }

  def committed
    get "/installments"
    last_response.body.include?("Hotel Exemplo")
  end

  def import_third(amount = "1.050,00")
    import.call(file_name: "Nubank_2026-09-09.csv", content: "date,title,amount\n2026-08-18,Hotel Exemplo - Parcela 3/6,\"#{amount}\"\n")
  end

  it "cancels every installment, drops the purchase from Parcelas, and cancels the ones imported later" do
    post "/transactions/#{hotel.last[:id]}/adjustment", kind: "canceled", scope: "purchase", note: "Booking canceled"

    expect(db[:transaction_adjustments].where(transaction_id: hotel.map { _1[:id] }).select_map(:kind)).to eq(%w[canceled canceled])
    expect(counted).to be_empty
    expect(committed).to be(false)

    import.call(file_name: "Nubank_2026-11-09.csv", content: fixture("Nubank_2026-11-09.csv"))
    import_third
    expect(db[:transaction_adjustments].where(transaction_id: hotel.last[:id]).get(:kind)).to eq("canceled")
    expect(counted).to be_empty

    get "/transactions/#{hotel.first[:id]}"
    expect(last_response.body).to include("Applies to every installment of this purchase", "3/6", "Booking canceled")
  end

  it "restores every installment when the whole purchase's adjustment is taken out, or just one" do
    post "/transactions/#{hotel.first[:id]}/adjustment", kind: "canceled", scope: "purchase"

    post "/transactions/#{hotel.first[:id]}/adjustment/remove"
    expect(counted).to eq([-105_000])

    post "/transactions/#{hotel.last[:id]}/adjustment/remove", scope: "purchase"
    expect(counted).to eq([-105_000, -105_000])
    expect(db[:purchase_adjustments].count).to eq(0)
    expect(committed).to be(true)
  end

  it "spreads a new total or what came back over the installments, like the bank splits the purchase" do
    post "/transactions/#{hotel.first[:id]}/adjustment", kind: "amount_changed", scope: "purchase", amount: "600.01"
    expect(counted).to eq([-10_001, -10_000])
    get "/installments"
    expect(last_response.body).to include("2 × R$ 100.00 = R$ 200.00")

    post "/transactions/#{hotel.first[:id]}/adjustment", kind: "reimbursed", scope: "purchase", amount: "3000.00"
    expect(db[:purchase_adjustments].count).to eq(1)
    expect(counted).to eq([-55_000, -55_000])

    import_third
    expect(counted).to eq([-55_000, -55_000, -55_000])

    post "/transactions/#{hotel.first[:id]}/adjustment", kind: "reimbursed", scope: "purchase", amount: "0.01"
    expect(counted).to eq([-104_999, -105_000, -105_000])
  end

  it "refuses what doesn't fit the purchase" do
    id = hotel.first[:id]
    [
      [{kind: "reimbursed", amount: "6300.01"}, "invalid_reimbursed_amount"],
      [{kind: "reimbursed", amount: ""}, "invalid_reimbursed_amount"],
      [{kind: "amount_changed", amount: "0.05"}, "invalid_adjusted_amount"],
      [{kind: "amount_changed", amount: ""}, "invalid_adjusted_amount"]
    ].each do |params, error|
      post "/transactions/#{id}/adjustment", **params, scope: "purchase"
      expect(last_response.location).to end_with("error=#{error}")
    end

    other = db[:transactions].exclude(kind: "transfer").where(installment_total: nil).get(:id)
    post "/transactions/#{other}/adjustment", kind: "canceled", scope: "purchase"
    expect(last_response.location).to end_with("error=not_installment")
    expect(db[:transaction_adjustments].count).to eq(0)
  end

  it "keeps a purchase whose first installment carries the rounding cents together" do
    import.call(file_name: "Nubank_2026-09-09.csv", content: "date,title,amount\n2026-08-20,Pousada Exemplo - Parcela 1/3,\"100,02\"\n")
    import.call(file_name: "Nubank_2026-10-09.csv", content: "date,title,amount\n2026-09-20,Pousada Exemplo - Parcela 2/3,\"99,99\"\n")
    inn = db[:transactions].where(description: "Pousada Exemplo").order(:installment_number).all
    expect(inn.map { _1[:purchase_key] }.uniq.size).to eq(2)

    post "/transactions/#{inn.last[:id]}/adjustment", kind: "canceled", scope: "purchase"
    expect(db[:transaction_adjustments].where(transaction_id: inn.map { _1[:id] }).count).to eq(2)
  end
end
