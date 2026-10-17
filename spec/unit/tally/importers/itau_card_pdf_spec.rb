# frozen_string_literal: true

RSpec.describe Tally::Importers::ItauCardPdf do
  def row(statement, description) = statement.rows.find { _1.raw_description == description }

  it "has fixtures that match the generator (spec/support/statements/build_fixtures.rb)" do
    ItauBills::FIXTURES.each do |name, bill|
      expect(fixture(name)).to eq(ItauBills.public_send(bill).to_pdf), "#{name} is stale; run build_fixtures.rb"
    end
  end

  describe "a bill with normal spacing, two and three columns per page" do
    let(:statement) { parse_fixture("itau_2026-10.pdf") }

    it "reads the printed summary" do
      expect(statement.card_statement).to eq(
        due_on: Date.new(2026, 10, 9), closing_on: Date.new(2026, 10, 2),
        total_cents: 266_158, previous_total_cents: 345_678, payments_cents: 345_678,
        purchases_cents: 260_908, fees_cents: 5_250,
        next_statement_cents: 188_788, later_statements_cents: 151_242,
        credit_limit_cents: 1_000_000, available_limit_cents: 432_109
      )
      expect(statement.warnings).to be_empty
    end

    it "reads every row of this bill, and none of the future installments" do
      expect(statement.rows.size).to eq(20)
      expect(statement.rows.map(&:kind).tally).to eq("transfer" => 1, "purchase" => 14, "refund" => 3, "fee" => 2)
      expect(statement.rows.reject { _1.kind == "transfer" }.sum { _1.amount.cents }).to eq(-266_158)
    end

    it "keeps the words of a description apart (1.2 pt gaps are spaces here)" do
      expect(row(statement, "Pagamento via conta")).to have_attributes(
        kind: "transfer", counter_account: "Itaú conta", amount: Tally::Money.new(345_678),
        occurred_on: Date.new(2026, 9, 2)
      )
    end

    it "reads the bank's category and city from the line below" do
      expect(row(statement, "FARMACIA EXEMPLO 4021")).to have_attributes(
        bank_category: "saúde", location: "SAO PAULO", amount: Tally::Money.new(-6_347),
        occurred_on: Date.new(2026, 9, 12), counterparty: {name: "FARMACIA EXEMPLO 4021"}
      )
      expect(row(statement, "SUPERMARKET EX").bank_category).to eq("supermarket")
      expect(row(statement, "POSTO EXEMPLO")).to have_attributes(bank_category: nil, location: nil)
    end

    it "drops the city glued to a merchant name" do
      expect(row(statement, "MERCADO EXEMPLOSAO PAUL").description).to eq("MERCADO EXEMPLO")
      expect(row(statement, "CAFE EXEMPLOSAO PAULOBR").description).to eq("CAFE EXEMPLO")
    end

    it "counts installments in the bill's month and keeps the purchase date" do
      expect(row(statement, "VOO EXEMPLO*AB12 08/10")).to have_attributes(
        description: "VOO EXEMPLO*AB12", installment_number: 8, installment_total: 10,
        occurred_on: Date.new(2026, 10, 2), purchased_on: Date.new(2026, 2, 2), amount: Tally::Money.new(-150_414)
      )
    end

    it "puts rows from after the closing month in the previous year" do
      expect(row(statement, "LOJA EXEMPLO 11/12").purchased_on).to eq(Date.new(2025, 11, 23))
      expect(row(statement, "PADARIA EXEMPLOSAO 10/10").purchased_on).to eq(Date.new(2025, 12, 27))
    end

    it "turns negative rows into refunds and the card fee and its discount into fees" do
      expect(row(statement, "CANCELAMENTO DE COMPRA")).to have_attributes(kind: "refund", amount: Tally::Money.new(3_290))
      expect(row(statement, "MARKETPLACE*EXEMPLO")).to have_attributes(kind: "refund", amount: Tally::Money.new(11_450))
      expect(row(statement, "Mensalidade - Plano do")).to have_attributes(kind: "fee", amount: Tally::Money.new(-10_500), counterparty: nil)
      expect(row(statement, "Redução Mensalidade - P")).to have_attributes(kind: "fee", amount: Tally::Money.new(5_250))
    end

    it "keeps two identical charges as two rows" do
      parking = statement.rows.select { _1.raw_description == "ESTACIONAMENTO EXEMPLO" }

      expect(parking.size).to eq(2)
      expect(parking.map(&:external_id).uniq.size).to eq(2)
    end

    it "keeps the cardholder and the line below in the raw row" do
      expect(row(statement, "FARMACIA EXEMPLO 4021").raw).to include(
        "cardholder" => "MARIA E SOUZA", "detail" => "saúde SAO PAULO", "section" => "purchases"
      )
    end
  end

  describe "a bill drawn with tight letter spacing" do
    let(:statement) { parse_fixture("itau_2027-01_tight.pdf") }

    it "glues the fragments back into words and amounts" do
      expect(statement.card_statement).to include(
        due_on: Date.new(2027, 1, 9), closing_on: Date.new(2027, 1, 2), total_cents: 69_100,
        purchases_cents: 63_850, fees_cents: 5_250, payments_cents: 210_000, next_statement_cents: 12_000
      )
      expect(statement.rows.map(&:raw_description)).to include("RESTAURANTE EXEMPLO", "PADARIA EXEMPLOSAO PAUL")
    end

    it "infers the year across New Year" do
      dates = statement.rows.to_h { [_1.raw_description, _1.purchased_on || _1.occurred_on] }

      expect(dates).to include(
        "Pagamento via conta" => Date.new(2026, 12, 2),
        "LOJA EXEMPLO 03/10" => Date.new(2026, 11, 15),
        "PADARIA EXEMPLOSAO PAUL" => Date.new(2026, 12, 20),
        "TRANSPORTE EXEMPLO" => Date.new(2027, 1, 1)
      )
    end
  end

  describe "a bill with an international purchase and a block of rows printed twice" do
    let(:statement) { parse_fixture("itau_2026-12_international.pdf") }

    it "adds the international purchase and its IOF to this bill's charges" do
      expect(statement.card_statement).to include(
        total_cents: 54_437, purchases_cents: 43_245 + 5_760, fees_cents: 5_250 + 202
      )
      expect(row(statement, "APP EXEMPLO UPGRADE")).to have_attributes(
        kind: "purchase", amount: Tally::Money.new(-5_760), occurred_on: Date.new(2026, 11, 20)
      )
      expect(row(statement, "Repasse de IOF")).to have_attributes(
        kind: "fee", amount: Tally::Money.new(-202), occurred_on: Date.new(2026, 12, 2), counterparty: nil
      )
    end

    it "imports the rows printed twice once, as the bill's total counts them, and says so" do
      credits = statement.rows.select { _1.occurred_on == Date.new(2026, 11, 15) }

      expect(credits.map { [_1.raw_description, _1.amount.cents] }).to eq(
        [["LOJA EXEMPLO", 5], ["MERCADO EXEMPLO", 12], ["LOJA EXEMPLO", 1], ["FARMACIA EXEMPLO", 2]]
      )
      expect(credits.map(&:kind).uniq).to eq(["refund"])
      expect(statement.rows.reject { _1.kind == "transfer" }.sum { _1.amount.cents }).to eq(-54_437)
      expect(statement.warnings).to contain_exactly(/4 rows adding up to -R\$ 0,20 are printed twice/)
    end

    it "rejects the bill when its total doesn't count the repeated rows once" do
      pdf = ItauBills.december.to_pdf.sub("(544,37)", "(544,57)")

      expect { described_class.new.call("fatura.pdf", pdf) }.to raise_error(
        Tally::Importers::Error, /Total desta fatura\), counting the 4 rows printed twice once/
      )
    end
  end

  describe "checks" do
    def parse(content) = described_class.new.call("fatura.pdf", content)

    it "rejects a bill whose rows don't add up to its printed totals" do
      # Same-length edit inside the content stream, so the PDF stays valid.
      tampered = ItauBills.october.to_pdf.sub("(189,30)", "(189,31)")

      expect { parse(tampered) }.to raise_error(
        Tally::Importers::Error, /purchases \(Lançamentos no cartão\): the rows add up to R\$ 2\.609,09, but the bill prints R\$ 2\.609,08/
      )
    end

    it "rejects a file poppler can't read" do
      expect { parse("%PDF-1.4 not really") }.to raise_error(Tally::Importers::Error, /pdftotext could not read/)
    end

    it "says what to install when pdftotext is missing" do
      parser = described_class.new(pdftotext: "pdftotext-that-does-not-exist")

      expect { parser.call("fatura.pdf", fixture("itau_2026-10.pdf")) }
        .to raise_error(Tally::Importers::Error, /apt install poppler-utils/)
    end

    it "warns, without rejecting, when the future installments don't match the next bill" do
      bill = ItauBills.october(later: "1.512,42")
      pdf = bill.to_pdf.sub("(1.887,88)", "(1.887,89)")

      statement = parse(pdf)
      expect(statement.warnings.first).to match(/future installments list adds up to R\$ 1\.887,88/)
      expect(statement.card_statement[:next_statement_cents]).to eq(188_789)
    end
  end
end
