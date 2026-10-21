# frozen_string_literal: true

require "rack/test"

RSpec.describe "Home bills", :db, type: :request do
  let(:db) { Hanami.app["db.gateway"].connection }
  let(:conta) { db[:accounts].insert(name: "Nubank conta", kind: "checking", person_id: me_id) }
  let(:energy_company) { db[:counterparties].insert(name: "Energia Exemplo", match_key: "|ENERGIA EXEMPLO") }
  let(:category) { db[:categories].insert(name: "Contas da casa", kind: "expense") }
  let(:storage) { Hanami.app.root.join(Hanami.app["settings"].receipt_storage_dir) }
  let(:png) { "\x89PNG\r\n\x1A\n".b + "fake receipt".b }

  def pay(occurred_on, cents, description, counterparty_id: nil)
    db[:transactions].insert(account_id: conta, occurred_on:, amount_cents: -cents, kind: "purchase", description:,
      raw_description: description, external_id: "fake-#{occurred_on}-#{cents}", counterparty_id:)
  end

  def create_bill(**params)
    post "/home-bills", {name: "Energia", category_id: category.to_s, expected: "182.40", due_day: "10"}.merge(params)
    db[:home_bills].order(:id).last
  end

  def upload(bill, content, month: "2026-10", name: "receipt.png")
    file = Rack::Test::UploadedFile.new(StringIO.new(content), "image/png", original_filename: name)
    post "/home-bills/#{bill[:id]}/receipts", month:, file:
  end

  before { allow(Date).to receive(:today).and_return(Date.new(2026, 10, 15)) }
  after { FileUtils.rm_rf(storage) }

  it "lists bills with how each month stands, and adds one from a subscription" do
    get "/home-bills"
    expect(last_response.body).to include("No home bills yet.")

    energy = create_bill(payee_key: "counterparty:#{energy_company}", payee_label: "Energia Exemplo")
    expect(last_response.location).to end_with("/home-bills/#{energy[:id]}")
    create_bill(name: "Internet", expected: "", due_day: "20", category_id: "")
    db[:home_bill_payments].insert(home_bill_id: energy[:id], month: "2026-09", paid_on: "2026-09-08", amount_cents: 17_510, paid_by: "Bruno")

    get "/home-bills"
    body = last_response.body
    expect(body).to include("Energia", "Contas da casa", "day 10", "R$ 182.40", "Internet", "day 20")
    expect(body).to include("paid on Sep 8, 2026 · R$ 175.10 · Bruno", "late", "due on Oct 20, 2026")
    expect(body).to include("R$ 182.40 a month", "2 late")

    get "/home-bills", payee: "counterparty:#{energy_company}", name: "Energia Exemplo", amount: "182.40", day: "8"
    expect(last_response.body).to include(%(name="payee_key" value="counterparty:#{energy_company}"), %(value="Energia Exemplo"), %(value="182.40"), %(value="8"))
  end

  it "refuses a bill without a name or a due day from 1 to 31" do
    post "/home-bills", name: "", due_day: "10"
    expect(last_response.status).to eq(422)
    post "/home-bills", name: "Água", due_day: "32"
    expect(last_response.status).to eq(422)
    post "/home-bills", name: "Água", due_day: "10", expected: "abc"
    expect(last_response.status).to eq(422)
    expect(last_response.body).to include("A bill needs a name, a due day from 1 to 31")
  end

  it "suggests the payment, links it by the bank's id so a re-import keeps it, and unlinks it" do
    energy = create_bill(payee_key: "counterparty:#{energy_company}", payee_label: "Energia Exemplo")
    september = pay("2026-09-09", 17_510, "ENERGIA EXEMPLO", counterparty_id: energy_company)
    october = pay("2026-10-08", 18_240, "ENERGIA EXEMPLO", counterparty_id: energy_company)
    pay("2026-10-09", 5_000, "MERCADO EXEMPLO")

    get "/home-bills/#{energy[:id]}"
    body = last_response.body
    expect(body).to include("Energia Exemplo", "late since Oct 10, 2026")
    expect(body).to include(%(<option value="#{october}" selected>), %(<option value="#{september}" selected>), "MERCADO EXEMPLO")
    expect(body).not_to include("Pick the row")

    post "/home-bills/#{energy[:id]}/payments", month: "2026-10", transaction_id: october.to_s
    expect(last_response.location).to end_with("/home-bills/#{energy[:id]}")

    # A re-import gives the row a new id; the bank's id stays.
    row = db[:transactions].where(id: october).first
    db[:transactions].where(id: october).delete
    again = db[:transactions].insert(row.except(:id))

    get "/home-bills/#{energy[:id]}"
    expect(last_response.body).to include("paid on Oct 8, 2026 · R$ 182.40 · Eu · Nubank conta", %(href="/transactions/#{again}?back=))
    expect(last_response.body).not_to include(%(<option value="#{again}"))

    post "/home-bills/#{energy[:id]}/payments/remove", month: "2026-10"
    expect(db[:home_bill_payments].count).to eq(0)
    post "/home-bills/#{energy[:id]}/payments", month: "2026-10", transaction_id: "999999"
    expect(last_response.status).to eq(404)
  end

  it "marks a month paid by hand, by you or whoever of the household paid" do
    energy = create_bill
    pay("2026-10-09", 5_000, "MERCADO EXEMPLO")
    get "/home-bills/#{energy[:id]}"
    expect(last_response.body).to include(%(<option value="" disabled selected>Pick the row</option>))
    expect(last_response.body).not_to include(%(name="person_id"))
    post "/home-bills/#{energy[:id]}/payments", month: "2026-09", paid_on: "2026-09-10", amount: "180.00"

    bruno = db[:people].insert(name: "Bruno")
    get "/home-bills/#{energy[:id]}"
    expect(last_response.body).to include("paid on Sep 10, 2026 · R$ 180.00 · Eu", %(<select name="person_id" data-picker>),
      %(<option value="#{me_id}" selected>Eu</option>), %(<option value="#{bruno}">Bruno</option>))
    post "/home-bills/#{energy[:id]}/payments", month: "2026-10", paid_on: "2026-10-10", amount: "190.00", person_id: bruno.to_s
    get "/home-bills/#{energy[:id]}"
    expect(last_response.body).to include("paid on Oct 10, 2026 · R$ 190.00 · Bruno")

    # A new name reaches the months they paid.
    post "/people/#{bruno}", name: "Beto"
    get "/home-bills/#{energy[:id]}"
    expect(last_response.body).to include("paid on Oct 10, 2026 · R$ 190.00 · Beto", "paid on Sep 10, 2026 · R$ 180.00 · Eu")

    post "/home-bills/#{energy[:id]}/payments", month: "2026-10", paid_on: "2026-10-10", amount: "190.00", person_id: "999"
    expect(last_response.status).to eq(422)
    post "/home-bills/#{energy[:id]}/payments", month: "2026-10", paid_on: "2026-10-40", amount: "190.00"
    expect(last_response.status).to eq(422)
    post "/home-bills/#{energy[:id]}/payments", month: "2026-13", paid_on: "2026-10-10", amount: "190.00"
    expect(last_response.status).to eq(422)
    post "/home-bills/#{energy[:id]}/payments", month: "2026-10", paid_on: "2026-10-10", amount: "-5"
    expect(last_response.status).to eq(422)
    post "/home-bills/#{energy[:id]}/payments", month: "2026-10", paid_on: "2026-10-10", amount: "x"
    expect(last_response.status).to eq(422)
  end

  it "keeps receipts on disk, serves them only through the app, and deletes them" do
    energy = create_bill
    upload(energy, png)
    upload(energy, png, month: "2026-09", name: "same file.png")
    expect(Dir.children(storage)).to eq([Digest::SHA256.hexdigest(png)])
    receipt = db[:home_bill_receipts].order(:id).first

    get "/home-bills/#{energy[:id]}"
    expect(last_response.body).to include(%(<a href="/receipts/#{receipt[:id]}"><img src="/receipts/#{receipt[:id]}" alt="receipt.png"))

    get "/receipts/#{receipt[:id]}"
    expect(last_response.body.b).to eq(png)
    expect(last_response.headers).to include("Content-Type" => "image/png", "Cache-Control" => "private, max-age=31536000, immutable",
      "X-Content-Type-Options" => "nosniff")

    upload(energy, "%PDF-1.7 fake", name: "boleto.pdf")
    get "/home-bills/#{energy[:id]}"
    expect(last_response.body).to include("boleto.pdf")

    upload(energy, "<svg/>")
    expect(last_response.status).to eq(422)
    expect(last_response.body).to include("A receipt is a JPEG, PNG or PDF")
    post "/home-bills/#{energy[:id]}/receipts", month: "2026-10"
    expect(last_response.status).to eq(422)

    post "/receipts/#{receipt[:id]}/delete"
    expect(last_response.location).to end_with("/home-bills/#{energy[:id]}")
    expect(Dir.children(storage).size).to eq(2) # the September row still uses the PNG
    post "/home-bills/#{energy[:id]}/delete"
    expect(last_response.location).to end_with("/home-bills")
    expect(Dir.children(storage)).to be_empty
    expect(db[:home_bill_receipts].count).to eq(0)

    get "/receipts/#{receipt[:id]}"
    expect(last_response.status).to eq(404)
    post "/receipts/#{receipt[:id]}/delete"
    expect(last_response.status).to eq(404)
    get "/home-bills/#{energy[:id]}"
    expect(last_response.status).to eq(404)
  end

  it "says a receipt file went missing from the disk" do
    energy = create_bill
    upload(energy, png)
    FileUtils.rm_rf(storage)
    get "/receipts/#{db[:home_bill_receipts].get(:id)}"
    expect(last_response.status).to eq(404)
  end
end
