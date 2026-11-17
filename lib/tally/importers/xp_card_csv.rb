# frozen_string_literal: true

module Tally
  module Importers
    # XP credit card bill export, named after its due date: Fatura2026-10-15.csv.
    #
    #   Data;Estabelecimento;Portador;Valor;Parcela
    #   06/10/2026;Pagamento de fatura;MARIA SOUZA;R$ -1.234,56; de 1
    #   10/09/2026;MERCADO EXEMPLO LTDA;MARIA SOUZA;R$ 123,45;-
    #   05/08/2026;ELETRO EXEMPLO;MARIA SOUZA;R$ 200,00;2 de 4
    #
    # UTF-8 with a BOM, CRLF, ";" between fields. Purchase dates, "R$" amounts, positive =
    # charge. No row ID, so the key is derived like the Nubank card's. The cardholder
    # (Portador) is ignored: the bill belongs to the person picked at import. See
    # docs/statement-import.md, section 2d.
    class XpCardCSV < CardBillCSV
      HEADER = "Data;Estabelecimento;Portador;Valor;Parcela"
      SOURCE = "xp_card_csv"
      ACCOUNT = "XP cartão"
      COL_SEP = ";"
      HEADER_ERROR = :xp_card_header
      FILE_NAME_ERROR = :xp_card_file_name

      DUE_DATE = /Fatura(\d{4}-\d{2}-\d{2})/
      PAYMENT = "Pagamento de fatura"
      INSTALLMENT = /\A\s*(\d+)\s+de\s+(\d+)\s*\z/

      private

      def row(record, line, due_on, repeats, warnings)
        date_text, name, holder, value, installment = Text.fields(record, line, 5)

        date = Text.date(date_text, "%d/%m/%Y", line)
        name = name.strip
        charge = charge(value, line, name, warnings) or return

        # A charge is money leaving the card account, so it is stored negative.
        amount = -charge
        k = repeats.next(date, name, charge.cents)

        Row.new(
          external_id: Importers.digest(SOURCE, due_on, date, name, charge.cents, k),
          amount:,
          raw_description: name,
          description: name,
          raw: {"date" => date_text, "name" => name, "holder" => holder, "amount" => value,
                "installment" => installment, "bill_due_on" => due_on.iso8601},
          **classify(name, amount, date, due_on, installment)
        )
      end

      def classify(name, amount, date, due_on, installment)
        if name == PAYMENT
          return {occurred_on: date, kind: "transfer", counter_account: "XP conta"}
        end

        fields = {occurred_on: date, kind: amount.negative? ? "purchase" : "refund", counterparty: {name:}}
        match = INSTALLMENT.match(installment)
        return fields unless match

        number, total = match[1].to_i, match[2].to_i
        fields.merge(
          **installment_dates(date, number, due_on),
          installment_number: number,
          installment_total: total,
          # Like the Nubank card's: what stays the same across bills.
          purchase_key: Importers.digest(SOURCE, name, total, amount.cents)
        )
      end

      # XP prints the purchase date on every installment, so installment N counts N - 1
      # months later. If that would pass the bill's due date, the date printed must already
      # be the installment's own, and it is kept.
      def installment_dates(date, number, due_on)
        posted = date >> (number - 1)
        return {occurred_on: date} if posted == date || posted > due_on

        {occurred_on: posted, purchased_on: date}
      end

      def summary(rows, due_on)
        payments, charges = rows.partition { _1.raw_description == PAYMENT }
        total = -charges.sum { _1.amount.cents }

        {
          due_on:,
          closing_on: nil,
          total_cents: total,
          payments_cents: payments.sum { _1.amount.cents },
          purchases_cents: total,
          fees_cents: 0
        }
      end
    end
  end
end
