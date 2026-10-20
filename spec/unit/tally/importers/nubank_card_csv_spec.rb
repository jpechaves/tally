# frozen_string_literal: true

RSpec.describe Tally::Importers::NubankCardCSV do
  let(:statement) { parse_fixture("Nubank_2026-07-09.csv") }
  let(:rows) { statement.rows }

  def row(title) = rows.find { _1.raw_description == title }

  def parse(content, file_name = "Nubank_2026-07-09.csv") = described_class.new.call(file_name, content)

  describe "IOF in the newer wording, which names no purchase" do
    let(:statement) { parse_fixture("Nubank_2026-11-09.csv") }

    it "imports \"IOF de compra internacional\" as a fee with no payee" do
      iofs = rows.select { _1.raw_description == "IOF de compra internacional" }
      expect(iofs.map { [_1.kind, _1.amount.cents, _1.counterparty] }).to eq([["fee", -350, nil], ["fee", -700, nil]])
      expect(row("IOF de volta de Loja Exemplo")).to have_attributes(kind: "refund", counterparty: {name: "Loja Exemplo"})
    end

    it "counts it in the bill's fees" do
      expect(statement.card_statement).to include(total_cents: 30_700, purchases_cents: 29_650, fees_cents: 1_050)
    end

    it "reads a refund of it as a refund" do
      refund = parse("date,title,amount\n2026-10-08,IOF de volta de compra internacional,\"- 3,50\"\n").rows.first
      expect(refund).to have_attributes(kind: "refund", counterparty: nil)
    end
  end

  describe "the synthetic bill due 2026-07-09" do
    it "reads every row, with the bill's due date from the file name" do
      expect(statement.source).to eq("nubank_card_csv")
      expect(statement.account_name).to eq("Nubank cartão")
      expect(rows.size).to eq(14)
      expect([statement.period_start, statement.period_end]).to eq([Date.new(2026, 6, 5), Date.new(2026, 6, 30)])
    end

    it "stores charges as negative amounts on the card account" do
      expect(row("Mercado Exemplo").amount).to eq(Tally::Money.new(-12_345))
      expect(row("Hotel Exemplo - Parcela 1/6").amount).to eq(Tally::Money.new(-105_000))
    end

    it "reads negatives written with a space as refunds" do
      expect(rows.select { _1.raw_description == "iFood - NuPay" }.map { [_1.kind, _1.amount.cents] })
        .to contain_exactly(["purchase", -4_780], ["refund", 2_150])
      expect(row('Estorno de "Loja Exemplo"')).to have_attributes(kind: "refund", counterparty: {name: "Loja Exemplo"})
      expect(row("Desconto Antecipação Doceria Exemplo")).to have_attributes(kind: "refund")
    end

    it "sums the bill: charges, payments and IOF fees" do
      expect(statement.card_statement).to eq(
        due_on: Date.new(2026, 7, 9), closing_on: nil,
        total_cents: 176_575, payments_cents: 99_900, purchases_cents: 176_379, fees_cents: 196
      )
    end

    it "marks the previous bill's payment as a transfer from the account" do
      expect(row("Pagamento recebido")).to have_attributes(
        kind: "transfer", counter_account: "Nubank conta", amount: Tally::Money.new(99_900)
      )
    end

    it "pairs IOF with its refund under the purchase's name" do
      iof = row('IOF de "Streaming Exemplo* Sub"')
      back = row("IOF de volta de Streaming Exemplo* Sub")

      expect(iof).to have_attributes(kind: "fee", counterparty: {name: "Streaming Exemplo* Sub"})
      expect(back).to have_attributes(kind: "refund", counterparty: {name: "Streaming Exemplo* Sub"})
      expect(iof.amount + back.amount).to eq(Tally::Money.zero)
    end

    it "reads a credited IOF of a purchase as a refund" do
      credit = parse(%(date,title,amount\n2026-06-10,"IOF de ""Loja Exemplo""","- 1,00"\n)).rows.first

      expect(credit).to have_attributes(kind: "refund", counterparty: {name: "Loja Exemplo"}, amount: Tally::Money.new(100))
    end

    it "reads installments and strips the suffix" do
      expect(row("Hotel Exemplo - Parcela 1/6")).to have_attributes(
        description: "Hotel Exemplo", installment_number: 1, installment_total: 6
      )
      expect(row("Pix no Crédito - JOAO EXEMPLO - 1/3")).to have_attributes(
        description: "Pix no Crédito - JOAO EXEMPLO", installment_number: 1, installment_total: 3,
        counterparty: {name: "JOAO EXEMPLO"}
      )
    end

    it "links nothing for a purchase paid at once" do
      expect(row("Mercado Exemplo")).to have_attributes(installment_number: nil, installment_total: nil, purchase_key: nil)
    end

    it "trims the spaces around a title and a payee" do
      rows = parse(<<~CSV).rows
        date,title,amount
        2026-06-10,  Hotel Exemplo - Parcela 1/6  ,"10,00"
        2026-06-11,Loja Exemplo  - NuPay,"5,00"
        2026-06-12,Estorno de  Loja Exemplo,"- 1,00"
        2026-06-13,Desconto Antecipação  Doceria Exemplo,"- 2,00"
      CSV

      expect(rows.map { [_1.raw_description, _1.description, _1.counterparty] }).to eq([
        ["Hotel Exemplo - Parcela 1/6", "Hotel Exemplo", {name: "Hotel Exemplo"}],
        ["Loja Exemplo  - NuPay", "Loja Exemplo  - NuPay", {name: "Loja Exemplo"}],
        ["Estorno de  Loja Exemplo", "Estorno de  Loja Exemplo", {name: "Loja Exemplo"}],
        ["Desconto Antecipação  Doceria Exemplo", "Desconto Antecipação  Doceria Exemplo", {name: "Doceria Exemplo"}]
      ])
    end

    it "links installments of one purchase across bills" do
      august = parse_fixture("Nubank_2026-08-09.csv").rows

      expect(august.find { _1.raw_description == "Hotel Exemplo - Parcela 2/6" }.purchase_key)
        .to eq(row("Hotel Exemplo - Parcela 1/6").purchase_key)
    end

    it "keeps two identical charges as two rows with different keys" do
      gym = rows.select { _1.raw_description == "Academia Exemplo" }

      expect(gym.size).to eq(2)
      # The bill prints charges as positive amounts, and the key keeps them that way.
      key = ->(k) { Tally::Importers.digest("nubank_card_csv", Date.new(2026, 7, 9), Date.new(2026, 6, 15), "Academia Exemplo", 18_990, k) }
      expect(gym.map(&:external_id)).to eq([key.call(0), key.call(1)])
    end

    it "derives the same keys every time" do
      expect(parse_fixture("Nubank_2026-07-09.csv").rows.map(&:external_id)).to eq(rows.map(&:external_id))
    end

    it "drops the NuPay suffix from the counterparty" do
      expect(rows.find { _1.raw_description == "iFood - NuPay" }.counterparty).to eq(name: "iFood")
    end
  end

  describe "checks" do
    it "needs the due date in the file name" do
      expect { parse(fixture("Nubank_2026-07-09.csv"), "fatura.csv") }
        .to raise_error(Tally::Importers::Error, /name the file after its due date/)
    end

    it "rejects a file with another header" do
      expect { parse("data,descricao,valor\n2026-06-10,Loja,\"1,00\"\n") }
        .to raise_error(Tally::Importers::Error, /not a Nubank card CSV: expected the header "date,title,amount"/)
    end

    it "rejects a due date in the file name that isn't a date" do
      expect { parse(fixture("Nubank_2026-07-09.csv"), "Nubank_2026-02-30.csv") }
        .to raise_error(Tally::Importers::Error, "the due date in the file name is not a valid date")
    end

    it "rejects a bill with no rows" do
      expect { parse("date,title,amount\n") }.to raise_error(Tally::Importers::Error, "the bill has no rows")
      expect { parse(%(date,title,amount\n2026-06-10,Loja,"0,00"\n)) }
        .to raise_error(Tally::Importers::Error, "the bill has no rows")
    end

    it "rejects a row with a missing or extra column" do
      expect { parse("date,title,amount\n2026-06-10,Loja\n") }
        .to raise_error(Tally::Importers::Error, "line 2: expected 3 columns")
      expect { parse(%(date,title,amount\n2026-06-10,Loja,"1,00"\n2026-06-11,Loja,"1,00",x\n)) }
        .to raise_error(Tally::Importers::Error, "line 3: expected 3 columns")
    end

    it "rejects an amount that isn't one" do
      expect { parse(%(date,title,amount\n2026-06-10,Loja,"12,3,4"\n)) }
        .to raise_error(Tally::Importers::Error, /line 2: not an amount/)
    end

    it "skips a zero amount with a warning" do
      statement = parse(%(date,title,amount\n2026-06-10,Loja,"0,00"\n2026-06-11,Loja,"1,00"\n))

      expect(statement.rows.size).to eq(1)
      expect(statement.warnings.map(&:to_s)).to eq(["line 2: zero amount, skipped: Loja"])
    end
  end
end
