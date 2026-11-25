# frozen_string_literal: true

require "fileutils"

# A Pix to Itaú's CNPJ that paid the Itaú card bill: a transfer to the card, paired with
# the bill's payment, never spending (and no detour through Itaú conta).
RSpec.describe "An Itaú card bill paid by Pix", :db do
  let(:db) { Hanami.app["db.gateway"].connection }

  after { FileUtils.rm_rf(Hanami.app.root.join(Hanami.app["settings"].import_storage_dir)) }

  let(:conta) do
    <<~CSV
      Data,Valor,Identificador,Descrição
      02/09/2026,-3456.78,d1b2c3d4-0000-4000-8000-000000000001,Transferência enviada pelo Pix - ITAU UNIBANCO HOLDING S A - 60.872.504/0001-23 - ITAÚ UNIBANCO S.A. (0341) Agência: 1 Conta: 99999-9
      10/09/2026,-50.00,d1b2c3d4-0000-4000-8000-000000000002,Transferência enviada pelo Pix - ITAU UNIBANCO HOLDING S A - 60.872.504/0001-23 - ITAÚ UNIBANCO S.A. (0341) Agência: 1 Conta: 99999-9
    CSV
  end

  def import(name, content = fixture(name))
    Hanami.app["operations.import_statement"].call(file_name: name, content:)
  end

  def account_id(name) = db[:accounts].where(name:).get(:id)

  def row(account, cents) = db[:transactions].where(account_id: account_id(account), amount_cents: cents).first

  def expect_paired
    sent = row("Nubank conta", -345_678)
    payment = row("Itaú cartão", 345_678)
    expect(sent).to include(kind: "transfer", counter_account_id: account_id("Itaú cartão"), category_id: nil)
    expect(payment).to include(counter_account_id: account_id("Nubank conta"))
    expect(sent[:transfer_id]).to eq(payment[:transfer_id]).and be_truthy
    expect(db[:transactions].where(account_id: account_id("Itaú conta")).count).to eq(0)
    # A Pix to Itaú that matches no bill payment stays what it was.
    expect(row("Nubank conta", -5_000)).to include(kind: "purchase", transfer_id: nil)
  end

  it "pairs it when your account comes first, and again after the bill is re-imported" do
    import("NU_11112222_01SEP2026_30SEP2026.csv", conta)
    import("itau_2026-10.pdf")
    expect_paired

    import("fatura-editada.pdf", ItauBills.october.to_pdf.sub("(1.887,88)", "(1.887,89)"))
    expect_paired
  end

  it "pairs it when the bill comes first, dropping the payment's Itaú conta side" do
    import("itau_2026-10.pdf")
    expect(row("Itaú conta", -345_678)).to be_truthy

    import("NU_11112222_01SEP2026_30SEP2026.csv", conta)
    expect_paired
  end
end
