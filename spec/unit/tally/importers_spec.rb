# frozen_string_literal: true

RSpec.describe Tally::Importers do
  it "picks the parser from the file's first bytes" do
    expect(described_class.for(fixture("NU_12345678_01JUL2026_31JUL2026.csv"))).to be_a(Tally::Importers::NubankAccountCSV)
    expect(described_class.for(fixture("Nubank_2026-07-09.csv"))).to be_a(Tally::Importers::NubankCardCSV)
    expect(described_class.for(fixture("itau_2026-10.pdf"))).to be_a(Tally::Importers::ItauCardPdf)
  end

  it "refuses anything else" do
    expect { described_class.for("Date,Amount\n") }.to raise_error(Tally::Importers::Error, /unknown file format/)
  end

  it "knows your Itaú account when a Pix goes to yourself there" do
    expect(described_class.self_account_for(bank_code: "0341", bank_name: nil)).to eq("Itaú conta")
    expect(described_class.self_account_for(bank_code: nil, bank_name: "ITAÚ UNIBANCO S.A.")).to eq("Itaú conta")
    expect(described_class.self_account_for(bank_code: "0260", bank_name: "NU PAGAMENTOS - IP")).to be_nil
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
