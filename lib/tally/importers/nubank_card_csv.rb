# frozen_string_literal: true

module Tally
  module Importers
    # Nubank credit card bill export, named after its due date: Nubank_2026-09-09.csv.
    #
    #   date,title,amount
    #   2026-09-29,Streaming Exemplo* Sub,"55,90"
    #   2026-09-02,Pagamento recebido,"- 4.321,09"
    #
    # ISO dates, comma-decimal amounts with "- " negatives, positive = charge. There is no
    # row ID, so the key is derived, numbering identical rows. See
    # docs/statement-import.md, section 2b.
    class NubankCardCSV < CardBillCSV
      HEADER = "date,title,amount"
      SOURCE = "nubank_card_csv"
      ACCOUNT = "Nubank cartão"
      COL_SEP = ","
      HEADER_ERROR = :nubank_card_header
      FILE_NAME_ERROR = :nubank_card_file_name

      DUE_DATE = /Nubank_(\d{4}-\d{2}-\d{2})/
      PAYMENT = "Pagamento recebido"
      INSTALLMENT = /\s+-\s+Parcela (\d+)\/(\d+)\z/
      PIX_INSTALLMENT = /\A(Pix no Crédito - .+?) - (\d+)\/(\d+)\z/
      NUPAY = / - NuPay\z/
      IOF = /\AIOF de "(.+)"\z/
      # Newer exports name no purchase: "IOF de compra internacional".
      IOF_INTERNATIONAL = /\AIOF de (?:volta de )?compra internacional\z/i
      IOF_REFUND = /\AIOF de volta de (.+)\z/
      REFUND = /\A(?:Estorno de "?(.+?)"?|Desconto Antecipação (.+))\z/

      private

      def row(record, line, due_on, repeats, warnings)
        date_text, title, value = Text.fields(record, line, 3)

        date = Text.date(date_text, "%Y-%m-%d", line)
        title = title.strip
        charge = charge(value, line, title, warnings) or return

        # A charge is money leaving the card account, so it is stored negative.
        amount = -charge
        k = repeats.next(date, title, charge.cents)

        Row.new(
          external_id: Importers.digest(SOURCE, due_on, date, title, charge.cents, k),
          occurred_on: date,
          amount:,
          raw_description: title,
          raw: {"date" => date_text, "title" => title, "amount" => value, "bill_due_on" => due_on.iso8601},
          **classify(title, amount)
        )
      end

      def classify(title, amount)
        by_sign = amount.negative? ? "purchase" : "refund"

        if title == PAYMENT
          return {kind: "transfer", description: title, counter_account: "Nubank conta"}
        end
        if IOF_INTERNATIONAL.match?(title)
          return {kind: amount.negative? ? "fee" : "refund", description: title}
        end
        if (match = IOF.match(title))
          return {kind: amount.negative? ? "fee" : "refund", description: title, counterparty: {name: match[1]}}
        end
        if (match = IOF_REFUND.match(title))
          return {kind: "refund", description: title, counterparty: {name: match[1]}}
        end
        if (match = REFUND.match(title))
          return {kind: "refund", description: title, counterparty: {name: (match[1] || match[2]).strip}}
        end

        name = title
        installment = nil
        if (match = INSTALLMENT.match(name))
          installment = [match[1].to_i, match[2].to_i]
          name = match.pre_match
        elsif (match = PIX_INSTALLMENT.match(name))
          installment = [match[2].to_i, match[3].to_i]
          name = match[1]
        end
        merchant = name.sub(NUPAY, "").delete_prefix("Pix no Crédito - ").strip

        fields = {kind: by_sign, description: name, counterparty: {name: merchant}}
        return fields unless installment

        number, total = installment
        fields.merge(
          installment_number: number,
          installment_total: total,
          # The export has no purchase date, so installments are linked by what stays the
          # same across bills: merchant, count and installment amount.
          purchase_key: Importers.digest(SOURCE, name, total, amount.cents)
        )
      end

      def summary(rows, due_on)
        payments, charges = rows.partition { _1.raw_description == PAYMENT }
        fees = charges.select { _1.kind == "fee" }

        {
          due_on:,
          closing_on: nil,
          total_cents: -charges.sum { _1.amount.cents },
          payments_cents: payments.sum { _1.amount.cents },
          purchases_cents: -(charges - fees).sum { _1.amount.cents },
          fees_cents: -fees.sum { _1.amount.cents }
        }
      end
    end
  end
end
