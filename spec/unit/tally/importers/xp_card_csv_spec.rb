# frozen_string_literal: true

RSpec.describe Tally::Importers::XpCardCSV do
  let(:statement) { parse_fixture("Fatura2026-10-15.csv") }
  let(:rows) { statement.rows }

  def row(name) = rows.find { _1.raw_description == name }

  def parse(body, file_name = "Fatura2026-10-15.csv")
    described_class.new.call(file_name, "#{described_class::HEADER}\r\n#{body}")
  end

  describe "the synthetic bill due 2026-10-15" do
    it "reads every row of the BOM and CRLF file, with the due date from the file name" do
      expect(statement).to have_attributes(source: "xp_card_csv", account_name: "XP cartão")
      expect(rows.size).to eq(10)
      expect([statement.period_start, statement.period_end]).to eq([Date.new(2026, 8, 5), Date.new(2026, 10, 6)])
    end

    it "stores charges negative and credits positive" do
      expect(row("MERCADO EXEMPLO LTDA")).to have_attributes(
        kind: "purchase", amount: Tally::Money.new(-12_345), counterparty: {name: "MERCADO EXEMPLO LTDA"}
      )
      expect(row("LOJA EXEMPLO")).to have_attributes(kind: "refund", amount: Tally::Money.new(2_500))
    end

    it "makes every bill payment, its own or the previous bill's, a transfer from XP conta" do
      payments = rows.select { _1.raw_description == "Pagamento de fatura" }

      expect(payments.map { [_1.kind, _1.counter_account, _1.amount.cents, _1.counterparty] })
        .to eq([["transfer", "XP conta", 123_456, nil], ["transfer", "XP conta", 45_678, nil]])
    end

    it "sums the bill: charges are its total, as XP prints none" do
      expect(statement.card_statement).to eq(
        due_on: Date.new(2026, 10, 15), closing_on: nil,
        total_cents: 162_755, payments_cents: 169_134, purchases_cents: 162_755, fees_cents: 0
      )
    end

    it "reads installments, counting a later one from its purchase date" do
      expect(row("HOTEL EXEMPLO")).to have_attributes(
        installment_number: 1, installment_total: 3, occurred_on: Date.new(2026, 9, 22), purchased_on: nil
      )
      expect(row("ELETRO EXEMPLO")).to have_attributes(
        installment_number: 2, installment_total: 4, occurred_on: Date.new(2026, 9, 5), purchased_on: Date.new(2026, 8, 5)
      )
      expect(row("MERCADO EXEMPLO LTDA")).to have_attributes(installment_number: nil, purchase_key: nil)
    end

    it "keeps two identical charges as two rows with different keys" do
      gym = rows.select { _1.raw_description == "ACADEMIA EXEMPLO" }
      key = ->(k) { Tally::Importers.digest("xp_card_csv", Date.new(2026, 10, 15), Date.new(2026, 9, 15), "ACADEMIA EXEMPLO", 9_990, k) }

      expect(gym.map(&:external_id)).to eq([key.call(0), key.call(1)])
    end
  end

  it "links installments of one purchase across bills" do
    next_bill = parse("05/08/2026;ELETRO EXEMPLO;MARIA SOUZA;R$ 200,00;3 de 4\r\n", "Fatura2026-11-15.csv").rows.first

    expect(next_bill).to have_attributes(occurred_on: Date.new(2026, 10, 5), purchase_key: row("ELETRO EXEMPLO").purchase_key)
  end

  it "keeps the printed date of an installment when counting from it would pass the due date" do
    installment = parse("10/10/2026;CURSO EXEMPLO;MARIA SOUZA;R$ 80,00;3 de 5\r\n").rows.first

    expect(installment).to have_attributes(occurred_on: Date.new(2026, 10, 10), purchased_on: nil)
  end

  describe "checks" do
    it "needs the due date in the file name" do
      expect { parse("10/09/2026;LOJA;MARIA;R$ 1,00;-\r\n", "fatura.csv") }
        .to raise_error(Tally::Importers::Error, /name the file after its due date, like Fatura2026-10-15.csv/)
      expect { parse("10/09/2026;LOJA;MARIA;R$ 1,00;-\r\n", "Fatura2026-02-30.csv") }
        .to raise_error(Tally::Importers::Error, "the due date in the file name is not a valid date")
    end

    it "rejects a file with another header" do
      expect { described_class.new.call("Fatura2026-10-15.csv", "Data;Valor\r\n10/09/2026;R$ 1,00\r\n") }
        .to raise_error(Tally::Importers::Error, /not an XP card CSV/)
    end

    it "rejects a bill with no rows, and skips a zero amount with a warning" do
      expect { parse("") }.to raise_error(Tally::Importers::Error, "the bill has no rows")

      statement = parse("10/09/2026;LOJA;MARIA;R$ 0,00;-\r\n11/09/2026;LOJA;MARIA;R$ 1,00;-\r\n")
      expect(statement.rows.size).to eq(1)
      expect(statement.warnings.map(&:to_s)).to eq(["line 2: zero amount, skipped: LOJA"])
    end

    it "rejects a row with a missing column" do
      expect { parse("10/09/2026;LOJA;MARIA;R$ 1,00\r\n") }.to raise_error(Tally::Importers::Error, "line 2: expected 5 columns")
    end
  end
end
