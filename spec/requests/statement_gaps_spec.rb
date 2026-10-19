# frozen_string_literal: true

require "fileutils"

RSpec.describe "Missing statements", :db, type: :request do
  let(:db) { Hanami.app["db.gateway"].connection }

  before do
    allow(Date).to receive(:today).and_return(Date.new(2026, 11, 15))
    %w[NU_12345678_01JUL2026_31JUL2026.csv Nubank_2026-07-09.csv Nubank_2026-08-09.csv Nubank_2026-11-09.csv].each do |name|
      Hanami.app["operations.import_statement"].(file_name: name, content: fixture(name))
    end
  end

  after { FileUtils.rm_rf(Hanami.app.root.join(Hanami.app["settings"].import_storage_dir)) }

  # A September conta file imported, with August's left out.
  def import_september(status: "applied")
    conta = db[:accounts].where(name: "Nubank conta").get(:id)
    db[:imports].insert(account_id: conta, source: "nubank_account_csv", file_name: "NU_12345678_01SET2026_30SET2026.csv",
      file_sha256: "1" * 64, file_size: 1, period_start: "2026-09-01", period_end: "2026-09-30", status:)
  end

  it "flags a conta month and card bills missing between imported ones on Contas" do
    import_september

    get "/accounts"

    expect(last_response.body).to include("missing the Aug 2026 statement", "missing the bills due from Sep 2026 to Oct 2026")
  end

  it "lists them on Importar, in Portuguese too" do
    import_september

    get "/imports"
    expect(last_response.body).to include("Missing statements", "Nubank conta: missing the Aug 2026 statement")

    set_cookie "locale=pt-BR"
    get "/imports"
    expect(last_response.body).to include("Extratos faltando", "Nubank conta: falta o extrato de ago/2026",
      "Nubank cartão: faltam as faturas com vencimento de set/2026 a out/2026")
  end

  it "ignores a file that was rejected" do
    import_september(status: "rejected")

    get "/accounts"

    expect(last_response.body).not_to include("missing the Aug 2026 statement")
    expect(last_response.body).to include("missing the bills due from Sep 2026 to Oct 2026")
  end
end
