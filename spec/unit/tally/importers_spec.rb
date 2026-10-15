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
end
