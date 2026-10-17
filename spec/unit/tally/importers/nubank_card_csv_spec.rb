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

    it "reads installments and strips the suffix" do
      expect(row("Hotel Exemplo - Parcela 1/6")).to have_attributes(
        description: "Hotel Exemplo", installment_number: 1, installment_total: 6
      )
      expect(row("Pix no Crédito - JOAO EXEMPLO - 1/3")).to have_attributes(
        description: "Pix no Crédito - JOAO EXEMPLO", installment_number: 1, installment_total: 3,
        counterparty: {name: "JOAO EXEMPLO"}
      )
    end

    it "links installments of one purchase across bills" do
      august = parse_fixture("Nubank_2026-08-09.csv").rows

      expect(august.find { _1.raw_description == "Hotel Exemplo - Parcela 2/6" }.purchase_key)
        .to eq(row("Hotel Exemplo - Parcela 1/6").purchase_key)
    end

    it "keeps two identical charges as two rows with different keys" do
      gym = rows.select { _1.raw_description == "Academia Exemplo" }

      expect(gym.size).to eq(2)
      expect(gym.map(&:external_id).uniq.size).to eq(2)
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

    it "rejects an amount that isn't one" do
      expect { parse(%(date,title,amount\n2026-06-10,Loja,"12,3,4"\n)) }
        .to raise_error(Tally::Importers::Error, /line 2: not an amount/)
    end

    it "skips a zero amount with a warning" do
      statement = parse(%(date,title,amount\n2026-06-10,Loja,"0,00"\n2026-06-11,Loja,"1,00"\n))

      expect(statement.rows.size).to eq(1)
      expect(statement.warnings).to eq(["line 2: zero amount, skipped: Loja"])
    end
  end
end
