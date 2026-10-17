# frozen_string_literal: true

RSpec.describe Tally::Importers::ContaGlobalCSV do
  let(:name) { "conta-global-2026-08.csv" }
  let(:statement) { parse_fixture(name) }
  let(:rows) { statement.rows }

  def row(key) = rows.find { _1.external_id == key }

  def usd(cents) = Tally::Money.new(cents, "USD")

  def parse(content) = described_class.new.call(name, content)

  # The fixture with one line's fields changed.
  def edited(line)
    lines = fixture(name).force_encoding("UTF-8").lines
    lines[line] = yield(lines[line])
    lines.join
  end

  describe "the synthetic statement" do
    it "reads every row into the dollar account, over the dates it covers" do
      expect(Tally::Importers.for(fixture(name))).to be_a(described_class)
      expect(statement.source).to eq("conta_global_csv")
      expect(statement.account_name).to eq("Nubank Conta Global")
      expect(rows.size).to eq(10)
      expect([statement.period_start, statement.period_end]).to eq([Date.new(2026, 7, 18), Date.new(2026, 8, 26)])
      expect(statement.warnings).to be_empty
    end

    it "keeps amounts in dollars, adding up to the last running balance" do
      expect(rows.map { _1.amount.currency }.uniq).to eq(["USD"])
      expect(Tally::Money.sum(rows.map(&:amount), "USD")).to eq(usd(11_304))
    end

    it "reads card rows as purchases at the merchant, from the description when Merchant is blank" do
      expect(row("CARD-8000000004@23-07-2026 10:00:00.000")).to have_attributes(
        kind: "purchase", amount: usd(-6_000), description: "Mercado Exemplo ORLANDO",
        counterparty: {name: "Mercado Exemplo ORLANDO"}, occurred_on: Date.new(2026, 7, 23)
      )
      expect(row("CARD-8000000001@21-07-2026 12:30:00.250")).to have_attributes(description: "Cafe Exemplo NEW YORK")
    end

    it "reads a CREDIT card row as a refund, even when it prints the amount negative" do
      expect(row("CARD-8000000005@24-07-2026 11:00:00.000")).to have_attributes(kind: "refund", amount: usd(2_000))
    end

    it "keeps every row of a card ID that repeats: a fare charged in parts, a hold and its reversal" do
      fare = rows.select { _1.external_id.start_with?("CARD-8000000003@") }
      hold = rows.select { _1.external_id.start_with?("CARD-8000000006@") }

      expect(fare.map { _1.amount.cents }).to contain_exactly(-890, -146)
      expect(hold.map { [_1.kind, _1.amount.cents] }).to contain_exactly(["purchase", -425], ["refund", 425])
    end

    it "keeps the exchange of a purchase in another currency: this row's part, the rate and the fee" do
      expect(row("CARD-8000000002@21-07-2026 18:45:10.500")).to have_attributes(
        amount: usd(-5_284), exchange_currency: "GBP", exchange_amount: Tally::Money.new(-4_120, "GBP"),
        exchange_rate: "0.7825", fee: usd(19)
      )
      expect(row("CARD-8000000003@22-07-2026 08:00:01.100").exchange_amount).to eq(Tally::Money.new(-200, "CAD"))
      expect(row("CARD-8000000004@23-07-2026 10:00:00.000")).to have_attributes(exchange_currency: nil, fee: nil)
    end

    it "reads a top-up as a transfer from Nubank conta, with the rate in reais per dollar" do
      expect(row("TRANSFER-9000000002@20-07-2026 09:15:30.120")).to have_attributes(
        kind: "transfer", counter_account: "Nubank conta", amount: usd(17_874),
        exchange_currency: "BRL", exchange_amount: nil, exchange_rate: "5.405405"
      )
    end

    it "keeps the row's own fields for audit" do
      expect(row("CARD-8000000002@21-07-2026 18:45:10.500").raw).to include(
        "TransferWise ID" => "CARD-8000000002", "Exchange To Amount" => "41.20", "Transaction Type" => "DEBIT"
      )
    end
  end

  describe "checks" do
    it "rejects a file whose running balance doesn't follow, as when a row is missing" do
      content = edited(4) { "" }

      expect { parse(content) }.to raise_error(Tally::Importers::Error, /line 4: the running balance is US\$ 113\.04, but the rows before it add up to US\$ 173\.04/)
    end

    it "warns when the file starts with money already in the account" do
      content = edited(10) { _1.sub(",50.00,BRL,", ",80.00,BRL,") }
      content = content.lines.map.with_index { |l, i| i.between?(1, 9) ? bump(l, 3_000) : l }.join

      expect(parse(content).warnings.map(&:to_s)).to eq(["the file starts with a balance of US$ 30.00: rows before it are not in this file"])
    end

    it "rejects rows in another currency" do
      content = edited(1) { _1.sub(",4.25,USD,", ",4.25,EUR,") }

      expect { parse(content) }.to raise_error(Tally::Importers::Error, /line 2: the amount is in "EUR"/)
    end

    it "rejects the same ID at the same time twice" do
      content = edited(2) { _1.sub("25-07-2026 03:10:05.400", "26-08-2026 03:12:44.081") }

      expect { parse(content) }.to raise_error(Tally::Importers::Error, /CARD-8000000006@26-08-2026 03:12:44.081 appears more than once/)
    end

    it "keeps a type it doesn't know, by its sign, with a warning" do
      content = edited(1) { _1.sub("CREDIT,CARD", "CREDIT,DEPOSIT") }

      expect(parse(content).rows.first).to have_attributes(kind: "income")
      expect(parse(content).warnings.map(&:to_s)).to eq(["line 2: transaction type DEPOSIT CREDIT not recognized, kept as is: " \
        "Transação por cartão de 4,25 USD emitida por Lavanderia Exemplo MIAMI"])
    end
  end

  # Raises a line's running balance by some cents.
  def bump(line, cents)
    fields = CSV.parse_line(line)
    fields[7] = format("%.2f", (BigDecimal(fields[7]) * 100 + cents) / 100)
    CSV.generate_line(fields)
  end
end
