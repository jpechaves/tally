# frozen_string_literal: true

RSpec.describe Tally::Importers::NubankAccountCSV do
  let(:name) { "NU_12345678_01JUL2026_31JUL2026.csv" }
  let(:statement) { parse_fixture(name) }
  let(:rows) { statement.rows }

  def row(description) = rows.find { _1.raw_description.include?(description) }

  def csv(*lines) = ([described_class::HEADER] + lines).join("\n") + "\n"

  describe "the synthetic July statement" do
    it "reads every row with its period from the file name" do
      expect(statement.source).to eq("nubank_account_csv")
      expect(statement.account_name).to eq("Nubank conta")
      expect([statement.period_start, statement.period_end]).to eq([Date.new(2026, 7, 1), Date.new(2026, 7, 31)])
      expect(rows.size).to eq(16)
      expect(rows.sum { _1.amount.cents }).to eq(205_003) # 9.820,00 in, 7.769,97 out
      expect(rows.map(&:kind).tally).to eq(
        "income" => 3, "purchase" => 6, "transfer" => 6, "bill_payment" => 1
      )
    end

    it "parses the signed dot-decimal amount and the DD/MM/YYYY date" do
      energy = row("ENERGIA EXEMPLO")

      expect(energy.amount).to eq(Tally::Money.new(-18_743))
      expect(energy.occurred_on).to eq(Date.new(2026, 7, 2))
    end

    it "keys rows by Identificador plus the sign" do
      expect(row("ENERGIA EXEMPLO").external_id).to eq("0b6f3a52-1d2e-4c8f-9a7b-5e4d3c2b1a00:-")
      expect(row("EMPRESA EXEMPLO").external_id).to eq("5f1c2a7e-0b3d-4e9a-8c71-2d4f6a8b0c11:+")
    end

    it "splits a Pix description into the counterparty and its bank details" do
      expect(row("ENERGIA EXEMPLO").counterparty).to eq(
        name: "ENERGIA EXEMPLO S.A.", document: "98.765.432/0001-10", document_kind: "cnpj",
        bank_name: "BCO DO BRASIL S.A.", bank_code: "0001", branch: "3309", account_number: "12345-6"
      )
      expect(row("ENERGIA EXEMPLO").description).to eq("ENERGIA EXEMPLO S.A.")
    end

    it "handles a masked CPF and a bank name that contains ' - '" do
      expect(row("JOSE DA SILVA").counterparty).to include(
        name: "JOSE DA SILVA EXEMPLO", document: "•••.123.456-••", document_kind: "cpf_masked",
        bank_name: "NU PAGAMENTOS - IP", bank_code: "0260"
      )
    end

    it "handles a bank with no code and a name that starts with digits" do
      expect(row("MEI EXEMPLO").counterparty).to include(
        name: "11.222.333 MEI EXEMPLO", document: "11.222.333/0001-44",
        bank_name: "ADYEN DO BRASIL IP LTDA.", bank_code: nil, branch: "1", account_number: "123456789-0"
      )
    end

    it "keeps a sender with no document as a name only" do
      expect(row("COMPANHIA AEREA").counterparty).to eq(name: "COMPANHIA AEREA EXEMPLO S/A.")
      expect(row("COMPANHIA AEREA").kind).to eq("income")
    end

    it "recognizes boletos and NuPay debit purchases" do
      expect(row("boleto")).to have_attributes(
        kind: "bill_payment", description: "FINANCEIRA EXEMPLO SOCIEDADE DE CREDITO"
      )
      expect(row("NuPay")).to have_attributes(kind: "purchase", description: "iFood", counterparty: {name: "iFood"})
    end

    it "marks moves between your own accounts as transfers to the right account" do
      expect(row("Aplicação RDB")).to have_attributes(kind: "transfer", counter_account: "Nubank RDB")
      expect(row("Resgate RDB")).to have_attributes(kind: "transfer", counter_account: "Nubank RDB")
      expect(row("Pagamento de fatura")).to have_attributes(kind: "transfer", counter_account: "Nubank cartão")
      expect(row("Conta Global")).to have_attributes(kind: "transfer", counter_account: "Nubank Conta Global")
    end

    it "makes both rows of a Pix no Crédito a pass-through transfer within the account" do
      pair = rows.select { _1.external_id.start_with?("8d0f2b4c") }

      expect(pair.map(&:external_id)).to contain_exactly(
        "8d0f2b4c-6e7a-4c9b-9dbe-5f7a9b1c3dcc:+", "8d0f2b4c-6e7a-4c9b-9dbe-5f7a9b1c3dcc:-"
      )
      expect(pair.map(&:kind).uniq).to eq(["transfer"])
      expect(pair.map(&:counter_account).uniq).to eq(["Nubank conta"])
      expect(pair.sum { _1.amount.cents }).to eq(0)
      expect(pair.find { _1.amount.negative? }.counterparty[:name]).to eq("SECRETARIA EXEMPLO")
    end

    it "keeps an unknown description as is, with a warning" do
      expect(row("Cobrança exemplo")).to have_attributes(
        kind: "purchase", description: "Cobrança exemplo, com vírgula", counterparty: nil
      )
      expect(statement.warnings).to eq(["line 17: description not recognized, kept as is: Cobrança exemplo, com vírgula"])
    end

    it "keeps the source row for audit" do
      expect(row("ENERGIA EXEMPLO").raw).to include("Data" => "02/07/2026", "Valor" => "-187.43")
    end
  end

  describe "checks" do
    let(:line) { "02/07/2026,-187.43,0b6f3a52-1d2e-4c8f-9a7b-5e4d3c2b1a00,Aplicação RDB" }

    def parse(content, file_name = name) = described_class.new.call(file_name, content)

    it "rejects another header" do
      expect { parse("Date,Amount\n1,2\n") }.to raise_error(Tally::Importers::Error, /header/)
    end

    it "rejects an amount with more than 2 decimals instead of rounding" do
      expect { parse(csv(line.sub("-187.43", "-187.435"))) }
        .to raise_error(Tally::Importers::Error, /line 2: more than 2 decimal places/)
    end

    it "rejects a date that doesn't exist" do
      expect { parse(csv(line.sub("02/07", "31/06"))) }.to raise_error(Tally::Importers::Error, /line 2: not a date/)
    end

    it "rejects an Identificador that repeats with the same sign, instead of merging rows" do
      expect { parse(csv(line, line.sub("Aplicação", "Resgate"))) }
        .to raise_error(Tally::Importers::Error, /appears more than once/)
    end

    it "rejects rows outside the period in the file name" do
      expect { parse(csv(line.sub("02/07", "02/08"))) }
        .to raise_error(Tally::Importers::Error, /outside the period/)
    end

    it "uses the first and last dates when the file name has no period" do
      statement = parse(csv(line), "extrato.csv")

      expect([statement.period_start, statement.period_end]).to eq([Date.new(2026, 7, 2)] * 2)
      expect(statement.warnings.first).to match(/no period/)
    end

    it "accepts a byte-order mark" do
      expect(parse("﻿#{csv(line)}").rows.size).to eq(1)
    end
  end
end
