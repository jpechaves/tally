# frozen_string_literal: true

require "bigdecimal"
require "csv"

module Tally
  module Importers
    # Nubank Conta Global (the dollar account) CSV export. The file has Wise's columns:
    #
    #   "TransferWise ID",Date,"Date Time",Amount,Currency,Description,...,"Running Balance",
    #   "Exchange From","Exchange To","Exchange Rate",...,Merchant,...,"Total fees",
    #   "Exchange To Amount","Transaction Type","Transaction Details Type"
    #   CARD-8000000002,21-07-2026,"21-07-2026 18:45:10.500",-52.84,USD,"Transação por cartão de 41,20 GBP emitida por Loja Exemplo LONDON",,163.40,USD,GBP,0.78250,...,0.19,41.20,DEBIT,CARD
    #
    # Newest row first, dates DD-MM-YYYY, signed amounts with a dot decimal, in the
    # account's currency (USD). The quirks (docs/statement-import.md, section 2c):
    #
    # - One card purchase can be several rows with the same ID: a transit fare charged in
    #   parts, or a purchase and, weeks later, its reversal as a CREDIT. So the key is the
    #   ID plus the row's timestamp.
    # - A refund is a CREDIT CARD row; its description may print the amount negative.
    # - A purchase in another currency carries the exchange: the amount in that currency
    #   ("Exchange To Amount", this row's part only), the rate, and the fee, which is
    #   already inside Amount.
    # - MONEY_ADDED is a top-up converted from BRL: a transfer from Nubank conta.
    # - Every row has the balance after it, so the whole file is checked to the cent.
    class ContaGlobalCSV
      HEADER_START = "\"TransferWise ID\","
      SOURCE = "conta_global_csv"
      ACCOUNT = "Nubank Conta Global"
      # Top-ups come from the BRL account ("Conversão para Conta Global" there).
      TOP_UP_FROM = "Nubank conta"

      REQUIRED = [
        "TransferWise ID", "Date", "Date Time", "Amount", "Currency", "Description", "Running Balance",
        "Transaction Type", "Transaction Details Type"
      ].freeze

      # "Transação por cartão de 41,20 GBP emitida por Loja Exemplo LONDON", or the
      # English export's "Card transaction of 41.20 GBP issued by Loja Exemplo LONDON".
      CARD_DESCRIPTION = /(?:emitida por|issued by)\s+(?<merchant>.+)\z/

      def call(_file_name, content)
        table = CSV.parse(Text.utf8(content), headers: true, skip_blanks: true)
        missing = REQUIRED - table.headers
        raise Error, "not a Conta Global CSV: missing the columns #{missing.join(", ")}" unless missing.empty?

        currency = Importers::ACCOUNTS.fetch(ACCOUNT)[:currency]
        warnings = []
        records = table.each.with_index(2).map { |record, line| read(record, line, currency) }
        raise Error, "the file has no rows" if records.empty?

        keys = records.map { _1[:key] }
        if (repeated = keys.tally.find { |_, count| count > 1 })
          raise Error, "#{repeated.first} appears more than once; refusing to merge rows"
        end

        records = records.sort_by { [_1[:time], -_1[:line]] }
        check_balances(records, currency, warnings)
        rows = records.map { row(_1, currency, warnings) }

        Statement.new(
          source: SOURCE, account_name: ACCOUNT, period_start: rows.map(&:occurred_on).min,
          period_end: rows.map(&:occurred_on).max, rows: rows.reverse, warnings:
        )
      end

      private

      def read(record, line, currency)
        fields = record.to_h.transform_values { _1.to_s.strip }
        unless fields["Currency"] == currency
          raise Error, "line #{line}: the amount is in #{fields["Currency"].inspect}; this account is in #{currency}"
        end

        id = fields["TransferWise ID"]
        raise Error, "line #{line}: no TransferWise ID" if id.empty?

        time = fields["Date Time"]
        raise Error, "line #{line}: not a date and time: #{time.inspect}" unless time.match?(/\A\d{2}-\d{2}-\d{4} \d{2}:\d{2}:\d{2}(\.\d+)?\z/)

        amount = money(fields["Amount"], currency, line)
        raise Error, "line #{line}: zero amount" if amount.zero?

        {
          line:, fields:, key: "#{id}@#{time}", amount:,
          date: Text.date(fields["Date"], "%d-%m-%Y", line),
          # "21-07-2026 18:45:10.500" -> "2026-07-21 18:45:10.500", which sorts in time order
          time: time.sub(/\A(\d{2})-(\d{2})-(\d{4})/, '\3-\2-\1'),
          balance: money(fields["Running Balance"], currency, line)
        }
      end

      # Each row's balance is the previous one plus its amount. The first row's previous
      # balance is what the account held before the file starts.
      def check_balances(records, currency, warnings)
        balance = records.first[:balance] - records.first[:amount]
        unless balance.zero?
          warnings << "the file starts with a balance of #{balance}: rows before it are not in this file"
        end

        records.each do |record|
          balance += record[:amount]
          next if balance == record[:balance]

          raise Error, "line #{record[:line]}: the running balance is #{record[:balance]}, " \
            "but the rows before it add up to #{balance}; is a row missing?"
        end
      end

      def row(record, currency, warnings)
        fields = record[:fields]
        amount = record[:amount]

        Row.new(
          external_id: record[:key],
          occurred_on: record[:date],
          amount:,
          raw_description: fields["Description"],
          fee: fee(fields, currency, record[:line]),
          raw: fields.reject { |_, value| value.empty? },
          **classify(fields, amount, record[:line], warnings),
          **exchange(fields, amount, currency, record[:line])
        )
      end

      # @return [Hash] kind, description, and counterparty / counter_account when known
      def classify(fields, amount, line, warnings)
        type = [fields["Transaction Details Type"], fields["Transaction Type"]]
        description = fields["Description"]

        case type
        in ["CARD", "DEBIT" | "CREDIT"]
          merchant = fields["Merchant"].to_s
          merchant = description[CARD_DESCRIPTION, :merchant].to_s.strip if merchant.empty?
          merchant = description if merchant.empty?
          {kind: amount.negative? ? "purchase" : "refund", description: merchant, counterparty: {name: merchant}}
        in ["MONEY_ADDED", "CREDIT"]
          {kind: "transfer", description:, counter_account: TOP_UP_FROM}
        else
          warnings << "line #{line}: transaction type #{type.join(" ")} not recognized, kept as is: #{description}"
          {kind: amount.negative? ? "purchase" : "income", description:}
        end
      end

      # The other currency of the row, if it had one. The file names the pair as From/To
      # with the rate in "To per From": a card purchase converts from the account's
      # currency (USD to GBP), a top-up converts into it (BRL to USD).
      def exchange(fields, amount, currency, line)
        from, to, rate = fields.values_at("Exchange From", "Exchange To", "Exchange Rate")
        return {} if from.to_s.empty? || to.to_s.empty? || from == to

        rate = decimal(rate, line)
        if from == currency
          other = fields["Exchange To Amount"].to_s
          exchange_amount = other.empty? ? nil : money(other, to, line).abs * (amount.negative? ? -1 : 1)
          {exchange_currency: to, exchange_amount:, exchange_rate: rate.to_s("F")}
        elsif to == currency
          # The amount converted from isn't printed; the rate is turned around so it reads
          # "BRL per USD" like the other rows'.
          {exchange_currency: from, exchange_rate: (1 / rate).round(6).to_s("F")}
        else
          raise Error, "line #{line}: an exchange from #{from} to #{to} doesn't involve #{currency}"
        end
      end

      def fee(fields, currency, line)
        text = fields["Total fees"].to_s
        return nil if text.empty?

        fee = money(text, currency, line).abs
        fee.zero? ? nil : fee
      end

      def money(text, currency, line)
        Money.parse(text, decimal: ".", currency:)
      rescue Money::ParseError => e
        raise Error, "line #{line}: #{e.message}"
      end

      def decimal(text, line)
        raise Error, "line #{line}: not an exchange rate: #{text.inspect}" unless text.to_s.match?(/\A\d+(\.\d+)?\z/)

        value = BigDecimal(text)
        raise Error, "line #{line}: zero exchange rate" if value.zero?

        value
      end
    end
  end
end
