# frozen_string_literal: true

require "fileutils"

RSpec.describe Tally::Operations::ImportStatement, :db do
  subject(:import_statement) { Hanami.app["operations.import_statement"] }

  let(:db) { Hanami.app["db.gateway"].connection }
  let(:storage) { Hanami.app.root.join(Hanami.app["settings"].import_storage_dir) }

  after { FileUtils.rm_rf(storage) }

  def import(name, content = fixture(name))
    import_statement.call(file_name: name, content:)
  end

  def account_id(name) = db[:accounts].where(name:).get(:id)

  def rows(account) = db[:transactions].where(account_id: account_id(account))

  def row(account, raw_description) = rows(account).where(raw_description:).first

  def balance(account) = rows(account).sum(:amount_cents).to_i

  describe "a first import" do
    it "writes every row, logs the import and keeps the file" do
      result = import("NU_12345678_01JUL2026_31JUL2026.csv")

      expect(result).to be_success
      expect(result.value!).to have_attributes(
        status: "applied", source: "nubank_account_csv", period_start: "2026-07-01", period_end: "2026-07-31",
        rows_inserted: 16, rows_updated: 0, rows_unchanged: 0, rows_missing: 0
      )
      expect(JSON.parse(result.value!.warnings).size).to eq(1)
      expect(rows("Nubank conta").count).to eq(16)
      expect(storage.join("#{result.value!.file_sha256}.csv")).to exist
    end

    it "imports an XP card bill, mirroring its payments into XP conta" do
      expect(import("Fatura2026-10-15.csv").value!).to have_attributes(source: "xp_card_csv", rows_inserted: 10)

      expect(rows("XP cartão").count).to eq(10)
      expect(rows("XP conta").select_map(:amount_cents)).to contain_exactly(-123_456, -45_678)
      expect(db[:card_statements].get(:total_cents)).to eq(162_755)
    end

    it "creates the accounts it needs" do
      import("NU_12345678_01JUL2026_31JUL2026.csv")

      expect(db[:accounts].select_map(:name)).to contain_exactly(
        "Nubank conta", "Nubank cartão", "Nubank RDB", "Nubank Conta Global"
      )
      expect(db[:accounts].where(name: "Nubank RDB").get(:mirror_transfers)).to eq(1)
    end

    it "stores amounts as integer cents and the source row as JSON" do
      import("NU_12345678_01JUL2026_31JUL2026.csv")
      energy = rows("Nubank conta").where(description: "ENERGIA EXEMPLO S.A.").first

      expect(energy).to include(amount_cents: -18_743, occurred_on: "2026-07-02", kind: "purchase")
      expect(JSON.parse(energy[:raw_json])).to include("Valor" => "-187.43")
    end

    it "keeps one counterparty per document and name, with its bank details" do
      import("NU_12345678_01JUL2026_31JUL2026.csv")

      expect(db[:counterparties].where(name: "ENERGIA EXEMPLO S.A.").first).to include(
        document: "98.765.432/0001-10", document_kind: "cnpj", bank_code: "0001", branch: "3309"
      )
    end

    it "makes a card merchant's variants one counterparty, named by its stable part" do
      repo = Hanami.app["repos.counterparty_repo"]
      ids = ["AEREA EXEMPLO*AB12", "AEREA EXEMPLO*CD34", "Aerea Exemplo", "AEREA EXEMPLO LINHAS*9876",
        "PAG*Aerea Exemplo"].map { repo.upsert(name: _1).id }

      expect(ids.uniq.size).to eq(1)
      expect(db[:counterparties].where(id: ids.first).get(:name)).to eq("AEREA EXEMPLO")

      cut = repo.upsert(name: "PADARIA EXEMPLO CENT").id
      expect(repo.upsert(name: "Padaria Exemplo Centro").id).to eq(cut)
      expect(repo.upsert(name: "PADARIA").id).not_to eq(cut)
      expect(repo.upsert(name: "AEREA EXEMPLO", document: "123.456.789-01").id).not_to eq(ids.first)
    end

    it "saves the card bill's figures" do
      import("itau_2026-10.pdf")

      expect(db[:card_statements].first).to include(
        due_on: "2026-10-09", closing_on: "2026-10-02", total_cents: 266_158, next_statement_cents: 188_788
      )
      expect(rows("Itaú cartão").exclude(card_statement_id: nil).count).to eq(20)
    end
  end

  describe "importing again" do
    it "logs the same bytes as a duplicate and writes nothing else" do
      import("Nubank_2026-07-09.csv")
      result = import("Nubank_2026-07-09.csv")

      expect(result.value!).to have_attributes(status: "duplicate_file", rows_inserted: 0)
      expect(db[:imports].count).to eq(2)
      expect(rows("Nubank cartão").count).to eq(14)
    end

    it "leaves the same rows unchanged when the bytes differ" do
      import("Nubank_2026-07-09.csv")
      result = import("Nubank_2026-07-09.csv", fixture("Nubank_2026-07-09.csv") + "\n")

      expect(result.value!).to have_attributes(status: "applied", rows_inserted: 0, rows_updated: 0, rows_unchanged: 14)
      expect(rows("Nubank cartão").count).to eq(14)
    end

    it "updates changed rows, flags missing ones, and never touches your memo" do
      import("NU_12345678_01JUL2026_31JUL2026.csv")
      energy = rows("Nubank conta").where(description: "ENERGIA EXEMPLO S.A.")
      energy.update(memo: "conta de luz de julho")

      edited = fixture("NU_12345678_01JUL2026_31JUL2026.csv").force_encoding("UTF-8")
        .sub("-187.43", "-187.44")
        .sub(/^08\/07\/2026.*\n/, "")
        .sub("Data,Valor,Identificador,Descrição\n",
          "Data,Valor,Identificador,Descrição\n31/07/2026,-9.99,3c5e7a9b-1d2f-4e6a-8b0c-2d4e6f8a0b21,Compra no débito via NuPay - Loja Exemplo\n")
      result = import("NU_12345678_01JUL2026_31JUL2026.csv", edited)

      expect(result.value!).to have_attributes(rows_inserted: 1, rows_updated: 1, rows_unchanged: 14, rows_missing: 1)
      expect(energy.first).to include(amount_cents: -18_744, memo: "conta de luz de julho")
      boleto = row("Nubank conta", "Pagamento de boleto efetuado - FINANCEIRA EXEMPLO SOCIEDADE DE CREDITO")
      expect(boleto[:missing_since_import_id]).to eq(result.value!.id)

      # The original file again, the very same bytes: it is applied, not skipped as a
      # duplicate, so the row comes back and the edit is undone.
      again = import("NU_12345678_01JUL2026_31JUL2026.csv")
      expect(again.value!).to have_attributes(status: "applied", rows_updated: 1)
      expect(row("Nubank conta", boleto[:raw_description])[:missing_since_import_id]).to be_nil
      expect(energy.first).to include(amount_cents: -18_743)

      # And once more: now it is the version in effect, so it is a duplicate.
      expect(import("NU_12345678_01JUL2026_31JUL2026.csv").value!.status).to eq("duplicate_file")
    end

    it "skips a card bill imported again whose period holds another bill's" do
      # A bill's period starts at its oldest installment's purchase date, so one bill's
      # period can hold another's: by period alone, the September bill imported after the
      # October one looks like a newer version of October's.
      import("itau_2026-10.pdf")
      september = ItauBills.october(closing: "02/09/2026", due: "09/09/2026").to_pdf
      import("fatura-setembro.pdf", september)
      oct, sep = db[:imports].order(:id).select_map(%i[period_start period_end])
      expect(sep.first >= oct.first && sep.last <= oct.last).to be(true)

      expect(import("itau_2026-10.pdf").value!.status).to eq("duplicate_file")
      expect(import("fatura-setembro.pdf", september).value!.status).to eq("duplicate_file")
    end

    it "applies a card bill's original again after an edited copy of the same bill" do
      import("itau_2026-10.pdf")
      edited = ItauBills.october.to_pdf.sub("(1.887,88)", "(1.887,89)")
      expect(import("fatura-editada.pdf", edited).value!.status).to eq("applied")

      expect(import("itau_2026-10.pdf").value!.status).to eq("applied")
      expect(import("itau_2026-10.pdf").value!.status).to eq("duplicate_file")
    end

    it "applies the original again after an edited copy under another name" do
      import("NU_12345678_01JUL2026_31JUL2026.csv")
      # Without the bank's name the period comes from the rows, so dropping the last
      # day's rows makes it shorter. The copy also drops one row inside that period.
      last_day = fixture("NU_12345678_01JUL2026_31JUL2026.csv").force_encoding("UTF-8").lines.drop(1).map { _1[0, 10] }.max_by { _1.split("/").reverse }
      edited = fixture("NU_12345678_01JUL2026_31JUL2026.csv").force_encoding("UTF-8").gsub(/^#{Regexp.escape(last_day)}.*\n/, "")
        .sub(/^08\/07\/2026.*\n/, "")
      copy = import("extrato-editado.csv", edited).value!
      expect(copy).to have_attributes(status: "applied")
      expect(copy.rows_missing).to eq(1)

      again = import("NU_12345678_01JUL2026_31JUL2026.csv")
      expect(again.value!).to have_attributes(status: "applied", rows_missing: 0)
      expect(rows("Nubank conta").exclude(missing_since_import_id: nil).count).to eq(0)
      expect(import("NU_12345678_01JUL2026_31JUL2026.csv").value!.status).to eq("duplicate_file")
    end

    it "only flags missing rows on the same card bill" do
      import("Nubank_2026-07-09.csv")
      import("Nubank_2026-08-09.csv")
      shorter = fixture("Nubank_2026-08-09.csv").force_encoding("UTF-8").sub(/^2026-07-10.*\n/, "")
      result = import("Nubank_2026-08-09.csv", shorter)

      expect(result.value!.rows_missing).to eq(1)
      expect(rows("Nubank cartão").exclude(missing_since_import_id: nil).select_map(:raw_description)).to eq(["Mercado Exemplo"])
    end
  end

  describe "a file that fails its checks" do
    it "is logged as rejected and nothing else is written" do
      tampered = ItauBills.october.to_pdf.sub("(189,30)", "(189,31)")
      result = import("fatura.pdf", tampered)

      expect(result).to be_failure
      expect(result.failure).to have_attributes(status: "rejected", source: "itau_card_pdf")
      expect(JSON.parse(result.failure.error)).to include("key" => "section_mismatch", "args" => include("section" => "purchases"))
      expect(db[:transactions].count).to eq(0)
      expect(db[:card_statements].count).to eq(0)
    end

    it "is logged as rejected when the format is unknown" do
      result = import("notes.csv", "Date,Amount\n1,2\n")

      expect(result.failure).to have_attributes(status: "rejected", source: "unknown")
    end
  end

  describe "transfers" do
    before do
      import("NU_12345678_01JUL2026_31JUL2026.csv")
      import("Nubank_2026-07-09.csv")
      import("Nubank_2026-08-09.csv")
      import("itau_2026-10.pdf")
    end

    it "pairs the account's bill payment with the payment the card received" do
      paid = row("Nubank conta", "Pagamento de fatura")
      received = rows("Nubank cartão").where(raw_description: "Pagamento recebido", amount_cents: 176_575).first

      expect(paid[:transfer_id]).not_to be_nil
      expect(received[:transfer_id]).to eq(paid[:transfer_id])
    end

    it "leaves a payment whose other side isn't imported as a one-leg transfer" do
      earlier = rows("Nubank cartão").where(raw_description: "Pagamento recebido", amount_cents: 99_900).first

      expect(earlier).to include(kind: "transfer", transfer_id: nil)
    end

    it "mirrors transfers into accounts that have no statement" do
      rdb = rows("Nubank RDB").order(:occurred_on).select_map(:amount_cents)

      expect(rdb).to eq([200_000, -50_000])
      expect(balance("Nubank RDB")).to eq(150_000)
      expect(rows("Itaú conta").select_map(:amount_cents)).to eq([-345_678])
    end

    it "pairs the two account rows of a Pix no Crédito with each other" do
      legs = rows("Nubank conta").where(Sequel.like(:external_id, "8d0f2b4c%")).all

      expect(legs.map { _1[:transfer_id] }.uniq.size).to eq(1)
      expect(legs.sum { _1[:amount_cents] }).to eq(0)
    end

    it "leaves the dollar account unmirrored" do
      expect(rows("Nubank Conta Global").count).to eq(0)
      expect(row("Nubank conta", "Conversão para Conta Global")).to include(kind: "transfer", transfer_id: nil)
    end

    it "keeps every transfer balanced" do
      sums = db[:transactions].exclude(transfer_id: nil).group(:transfer_id).select_map { sum(:amount_cents) }

      expect(sums.uniq).to eq([0])
    end

    it "pairs nothing twice when everything is imported again" do
      count = db[:transfers].count
      import("NU_12345678_01JUL2026_31JUL2026.csv", fixture("NU_12345678_01JUL2026_31JUL2026.csv") + "\n")
      import("Nubank_2026-08-09.csv", fixture("Nubank_2026-08-09.csv") + "\n")

      expect(db[:transfers].count).to eq(count)
      expect(rows("Nubank RDB").count).to eq(2)
    end

    it "follows a changed amount into the mirror row" do
      edited = fixture("NU_12345678_01JUL2026_31JUL2026.csv").force_encoding("UTF-8").sub("-2000.00", "-2100.00")
      import("NU_12345678_01JUL2026_31JUL2026.csv", edited)

      expect(balance("Nubank RDB")).to eq(160_000)
    end
  end

  describe "a Conta Global statement" do
    let(:global) { "conta-global-2026-08.csv" }
    let(:nubank) { "NU_12345678_01JUL2026_31JUL2026.csv" }

    def top_up(time) = rows("Nubank Conta Global").where(external_id: "TRANSFER-#{time}").first

    def conversion = row("Nubank conta", "Conversão para Conta Global")

    it "writes the dollar account's rows in dollars, with their exchange" do
      expect(import(global).value!).to have_attributes(status: "applied", source: "conta_global_csv", rows_inserted: 10)

      expect(db[:accounts].where(name: "Nubank Conta Global").get(:currency)).to eq("USD")
      expect(balance("Nubank Conta Global")).to eq(11_304)
      expect(rows("Nubank Conta Global").where(external_id: "CARD-8000000002@21-07-2026 18:45:10.500").first).to include(
        kind: "purchase", amount_cents: -5_284, exchange_currency: "GBP", exchange_amount_cents: -4_120,
        exchange_rate: "0.7825", fee_cents: 19
      )
    end

    [%w[global nubank], %w[nubank global]].each do |order|
      it "pairs a top-up with its conversion in Nubank conta (#{order.join(" first, then ")})" do
        order.each { import(send(_1)) }

        # R$ 1.000,00 with IOF bought US$ 178,74 at R$ 5,405405 per dollar
        paired = top_up("9000000002@20-07-2026 09:15:30.120")
        expect(paired).to include(kind: "transfer", counter_account_id: account_id("Nubank conta"))
        expect(paired[:transfer_id]).to be_an(Integer).and eq(conversion[:transfer_id])
        # The other top-up's BRL side isn't in any imported file.
        expect(top_up("9000000001@18-07-2026 10:00:00.000")).to include(kind: "transfer", transfer_id: nil)
      end
    end

    it "unpairs them when a re-import changes the conversion beyond what the rate allows" do
      import(global)
      import(nubank)
      import(nubank, fixture(nubank).force_encoding("UTF-8").sub("-1000.00", "-1500.00"))

      expect(conversion).to include(amount_cents: -150_000, transfer_id: nil)
      expect(top_up("9000000002@20-07-2026 09:15:30.120")[:transfer_id]).to be_nil
    end

    it "updates rows on re-import instead of duplicating them" do
      import(global)
      result = import(global, fixture(global) + "\n").value!

      expect(result).to have_attributes(rows_inserted: 0, rows_updated: 0, rows_unchanged: 10)
      expect(rows("Nubank Conta Global").count).to eq(10)
    end

    it "rejects a statement whose amounts aren't in its account's currency" do
      statement = Tally::Importers.parse(global, fixture(global))
      brl = statement.rows.map { _1.with(amount: Tally::Money.new(_1.amount.cents)) }
      allow(Tally::Importers).to receive(:parse).and_return(statement.with(rows: brl))

      result = import(global)

      expect(result).to be_failure
      expect(Hanami.app["repos.import_repo"].error(result.failure).to_s).to match(/amount in BRL, but Nubank Conta Global is in USD/)
      expect(db[:transactions].count).to eq(0)
    end
  end

  describe "a Pix to yourself" do
    let(:mark_self) { Hanami.app["operations.mark_self"] }
    let(:me) { db[:counterparties].where(name: "MARIA E SOUZA").first }

    before { import("NU_12345678_01JUL2026_31JUL2026.csv") }

    it "becomes a transfer to your Itaú account once you mark yourself" do
      expect(row("Nubank conta", described_row)[:kind]).to eq("purchase")

      expect(mark_self.call(counterparty_id: me[:id], person_id: me_id)).to be_success

      pix = row("Nubank conta", described_row)
      expect(pix).to include(kind: "transfer", counter_account_id: account_id("Itaú conta"))
      expect(rows("Itaú conta").first).to include(amount_cents: 150_000, transfer_id: pix[:transfer_id])
    end

    it "nets out against the card bill the Itaú account paid" do
      mark_self.call(counterparty_id: me[:id], person_id: me_id)
      import("itau_2026-10.pdf")

      # Pix in 1.500,00, bill paid 3.456,78: the account would be 1.956,78 short, which the
      # accounts page flags as above the pass-through tolerance.
      expect(balance("Itaú conta")).to eq(-195_678)
    end

    it "stays a transfer on re-import, and goes back when you unmark yourself" do
      mark_self.call(counterparty_id: me[:id], person_id: me_id)
      import("NU_12345678_01JUL2026_31JUL2026.csv", fixture("NU_12345678_01JUL2026_31JUL2026.csv") + "\n")
      expect(row("Nubank conta", described_row)[:kind]).to eq("transfer")

      mark_self.call(counterparty_id: me[:id], person_id: nil)
      expect(row("Nubank conta", described_row)).to include(kind: "purchase", transfer_id: nil, counter_account_id: nil)
      expect(rows("Itaú conta").count).to eq(0)
    end

    def described_row
      rows("Nubank conta").where(counterparty_id: me[:id]).get(:raw_description)
    end
  end
end
