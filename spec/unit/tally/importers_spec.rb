# frozen_string_literal: true

RSpec.describe Tally::Importers do
  it "picks the parser from the file's first bytes" do
    expect(described_class.for(fixture("NU_12345678_01JUL2026_31JUL2026.csv"))).to be_a(Tally::Importers::NubankAccountCSV)
    expect(described_class.for(fixture("Nubank_2026-07-09.csv"))).to be_a(Tally::Importers::NubankCardCSV)
    expect(described_class.for(fixture("itau_2026-10.pdf"))).to be_a(Tally::Importers::ItauCardPdf)
    expect(described_class.for(fixture("Fatura2026-10-15.csv"))).to be_a(Tally::Importers::XpCardCSV)
  end

  it "refuses anything else" do
    expect { described_class.for("Date,Amount\n") }.to raise_error(Tally::Importers::Error, /unknown file format/)
  end

  it "knows the account a Pix to someone of the household went to, from the bank its text names" do
    expect(described_class.account_at("Pix - ANA - BANCO (0341) Agência: 1 Conta: 2")).to eq("Itaú conta")
    expect(described_class.account_at("Pix - ANA - ITAÚ UNIBANCO S.A. Agência: 1 Conta: 2")).to eq("Itaú conta")
    expect(described_class.account_at("Pix - ANA - NU PAGAMENTOS - IP (0260) Agência: 1 Conta: 2")).to eq("Nubank conta")
    expect(described_class.account_at("Pix - ANA - BANCO XP S.A. (0348) Agência: 1 Conta: 2")).to eq("XP conta")
    expect(described_class.account_at("Pix - ANA - PICPAY (0380) Agência: 1 Conta: 2")).to be_nil
  end

  it "keeps row keys the same from one version to the next, or a re-import would duplicate rows" do
    expect(described_class.digest("nubank_card_csv", Date.new(2026, 7, 9), "Loja", 1_000, 0))
      .to eq(Digest::SHA256.hexdigest("nubank_card_csv|2026-07-09|Loja|1000|0")[0, 32])
    expect(described_class.digest("a", 1)).to eq("df4504ce92500fe8a20fb37090e36afa")
  end

  it "refuses a file that isn't UTF-8" do
    expect { described_class::Text.utf8("Data,Valor\n\xFF\n".b) }
      .to raise_error(Tally::Importers::Error, "the file is not valid UTF-8")
  end

  describe Tally::Importers::Notice do
    it "is stored as its key and values, and read back in either language" do
      stored = described_class[:zero_amount_skipped, line: 3, text: "Loja"].to_h

      expect(stored).to eq("key" => "zero_amount_skipped", "args" => {"line" => 3, "text" => "Loja"})
      notice = described_class.load(stored)
      expect(notice.to_s).to eq("line 3: zero amount, skipped: Loja")
      expect(notice.text("pt-BR")).not_to eq(notice.to_s)
    end

    it "writes amounts in the notice's currency, reais by default" do
      expect(described_class[:opening_balance, balance_cents: 3_000, currency: "USD"].to_s)
        .to include("US$ 30.00")
      expect(described_class[:opening_balance, balance_cents: 3_000].to_s).to include("R$ 30.00")
    end

    it "reads back the plain text older imports stored" do
      expect(described_class.load("line 2: zero amount")).to eq("line 2: zero amount")
    end
  end
end
