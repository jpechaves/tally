# frozen_string_literal: true

require "fileutils"

RSpec.describe "Languages", :db, type: :request do
  let(:db) { Hanami.app["db.gateway"].connection }

  before do
    clear_cookies
    allow(Date).to receive(:today).and_return(Date.new(2026, 8, 15))
    %w[NU_12345678_01JUL2026_31JUL2026.csv Nubank_2026-07-09.csv Nubank_2026-08-09.csv].each do |name|
      Hanami.app["operations.import_statement"].(file_name: name, content: fixture(name))
    end
  end

  after { FileUtils.rm_rf(Hanami.app.root.join(Hanami.app["settings"].import_storage_dir)) }

  it "speaks Portuguese by default, with Brazilian amounts, dates and months" do
    get "/report?month=2026-07"
    body = last_response.body
    expect(body).to include('<html lang="pt-BR">', "<h1>Para onde foi o dinheiro</h1>", "Receitas<strong>R$ 8.920,00</strong>")
    expect(body).to include(%(<option value="2026-07" selected>jul/2026</option>), "Médias de jun/2026.")
    expect(body).to include(%(<button type="submit" name="locale" value="en" lang="en">English</button>))

    get "/transactions?month=2026-07"
    expect(last_response.body).to match(%r{<td>\d\d/07/2026</td>}).and include("<td>compra</td>")
  end

  it "switches to English and back, remembering the choice in a cookie" do
    post "/locale", locale: "en", back: "/report?month=2026-07"
    expect(last_response.status).to eq(302)
    expect(last_response.headers["Location"]).to end_with("/report?month=2026-07")
    expect(last_response.headers["Set-Cookie"]).to include("locale=en", "samesite=lax")

    follow_redirect!
    expect(last_response.body).to include('<html lang="en">', "<h1>Where the money went</h1>", "Income<strong>R$ 8,920.00</strong>")

    post "/locale", locale: "pt-BR", back: "/cuts"
    follow_redirect!
    expect(last_response.body).to include("<h1>O que posso cortar?</h1>")
  end

  it "refuses an unknown language, and only goes back to a page on this site" do
    post "/locale", locale: "fr"
    expect(last_response.status).to eq(422)

    post "/locale", locale: "en", back: "//evil.example/x"
    expect(last_response.headers["Location"]).to end_with("/")
    expect(last_response.headers["Location"]).not_to include("evil")

    post "/locale", locale: "en"
    expect(last_response.headers["Location"]).to end_with("/")
  end

  it "reads amounts typed in forms with the language's decimal mark" do
    post "/plan", target: "2.500,00", starts_month: "2026-09"
    expect(db[:savings_plans].get(:target_cents)).to eq(250_000)

    follow_redirect!
    delivery = db[:categories].where(name: "Delivery").get(:id)
    expect(last_response.body).to include("Guardar R$ 2.500,00 por mês")
    expect(last_response.body).to match(/name="proposed\[#{delivery}\]" class="amount" value="\d+,\d\d"/)

    set_cookie "locale=en"
    get last_request.path
    expect(last_response.body).to match(/name="proposed\[#{delivery}\]" class="amount" value="\d+\.\d\d"/)
  end

  it "words cut suggestions in Portuguese" do
    allow(Date).to receive(:today).and_return(Date.new(2026, 10, 15))
    %w[itau_2026-10.pdf itau_2027-01_tight.pdf].each do |name|
      Hanami.app["operations.import_statement"].(file_name: name, content: fixture(name))
    end

    get "/cuts?month=2026-09"
    expect(last_response.body).to include("<h1>O que posso cortar?</h1>", "Tarifas, juros e financiamentos: R$ 52,50",
      "Possível cobrança em dobro", "ESTACIONAMENTO EXEMPLO: R$ 14,00 cobrado 2 vezes")
    expect(last_response.body).to match(/cerca de R\$ [\d.]+,\d\d por mês/)
  end

  it "translates starting category names, but not the ones you named" do
    get "/transactions?month=2026-07"
    expect(last_response.body).to include("<td>Delivery</td>")

    set_cookie "locale=en"
    get "/transactions?month=2026-07"
    expect(last_response.body).to include("<td>Food delivery</td>")

    delivery = db[:categories].where(name: "Delivery").get(:id)
    post "/categories/#{delivery}", name: "Food delivery", nature: "discretionary"
    expect(db[:categories].where(id: delivery).get(:name)).to eq("Delivery")

    post "/categories/#{delivery}", name: "Comida pedida", nature: "discretionary"
    get "/transactions?month=2026-07"
    expect(last_response.body).to include("<td>Comida pedida</td>")
    clear_cookies
    get "/transactions?month=2026-07"
    expect(last_response.body).to include("<td>Comida pedida</td>")
  end
end
