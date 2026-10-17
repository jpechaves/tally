# frozen_string_literal: true

require "csv"

module Tally
  module Importers
    # Nubank account (conta) CSV export, e.g. NU_<account>_01JUN2026_30JUN2026.csv.
    #
    #   Data,Valor,Identificador,Descrição
    #   08/06/2026,-187.43,0b6f3a52-...,Transferência enviada pelo Pix - NAME - DOC - BANK (CODE) Agência: A Conta: C
    #
    # Dates are DD/MM/YYYY, amounts are signed with a dot decimal, and Identificador is a
    # UUID that repeats only for a "Pix no Crédito" pair, so the key is UUID + sign.
    # See docs/statement-import.md, section 2.
    class NubankAccountCSV
      HEADER = "Data,Valor,Identificador,Descrição"
      SOURCE = "nubank_account_csv"
      ACCOUNT = "Nubank conta"

      MONTHS = %w[JAN FEV MAR ABR MAI JUN JUL AGO SET OUT NOV DEZ].freeze
      PERIOD = /(\d{2})(#{MONTHS.join("|")})(\d{4})_(\d{2})(#{MONTHS.join("|")})(\d{4})/
      UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

      # "NAME - DOC - BANK (CODE) Agência: A Conta: C". Names and bank names can contain
      # " - " themselves ("NU PAGAMENTOS - IP"), so the document is the anchor.
      DOCUMENT = /(?<document>\d{2}\.\d{3}\.\d{3}\/\d{4}-\d{2}|•••\.\d{3}\.\d{3}-••)/
      PARTY = /\A(?<name>.+?) - #{DOCUMENT}(?: - (?<bank>.*))?\z/
      BANK = /\A(?:(?<bank_name>.*?)\s*(?:\((?<bank_code>\d+)\))?\s*)?Agência: (?<branch>\S+) Conta: (?<account_number>\S+)\z/

      PIX_OUT = "Transferência enviada pelo Pix - "
      PIX_IN = "Transferência recebida pelo Pix - "
      TRANSFER_IN = "Transferência Recebida - "
      BOLETO = "Pagamento de boleto efetuado - "
      NUPAY = "Compra no débito via NuPay - "
      DEBIT = "Compra no débito - "
      PIX_REFUND = "Reembolso recebido pelo Pix - "
      PHONE_TOP_UP = "Recarga de celular"
      CARD_TOP_UP = "Valor adicionado na conta por cartão de crédito"

      # Fixed descriptions that move money between your own accounts.
      TRANSFERS = {
        "Pagamento de fatura" => "Nubank cartão",
        "Aplicação RDB" => "Nubank RDB",
        "Resgate RDB" => "Nubank RDB",
        "Conversão para Conta Global" => "Nubank Conta Global"
      }.freeze

      def call(file_name, content)
        text = Text.utf8(content)
        table = CSV.parse(text, headers: true, skip_blanks: true)
        unless table.headers == HEADER.split(",")
          raise Error.new(:nubank_account_header, header: HEADER.inspect)
        end

        records = table.each.with_index(2).map { |record, line| read(record, line) }
        rows, warnings = describe(records)

        keys = rows.map(&:external_id)
        if (repeated = keys.tally.find { |_, count| count > 1 })
          raise Error.new(:repeated_identificador, id: repeated.first)
        end

        period_start, period_end = period(file_name, rows, warnings)

        Statement.new(
          source: SOURCE, account_name: ACCOUNT, period_start:, period_end:, rows:, warnings:
        )
      end

      private

      def read(record, line)
        date_text, value, id, description = record.fields
        raise Error.new(:columns, line:, columns: 4) if description.nil? || record.fields.size != 4

        id = id.strip
        raise Error.new(:not_a_uuid, line:, text: id.inspect) unless UUID.match?(id)

        amount = Text.amount(value, line, decimal: ".")
        raise Error.new(:zero_amount, line:) if amount.zero?

        {line:, date: Text.date(date_text, "%d/%m/%Y", line), amount:, id:, description: description.strip}
      end

      def describe(records)
        warnings = []
        # A Pix paid with the credit card: "+X Valor adicionado ..." and "-X Pix" share a
        # UUID. The spending is the card's "Pix no Crédito" row; both account rows are
        # pass-through, a transfer whose two legs are in this account.
        top_ups = records.select { _1[:description].start_with?(CARD_TOP_UP) }.map { _1[:id] }.to_set

        rows = records.map do |record|
          fields = classify(record[:description], record[:amount])
          if top_ups.include?(record[:id])
            fields = fields.merge(kind: "transfer", counter_account: ACCOUNT)
          end
          if fields.delete(:unparsed)
            warnings << Notice[:description_not_recognized, line: record[:line], text: record[:description]]
          end

          Row.new(
            external_id: "#{record[:id]}:#{record[:amount].negative? ? "-" : "+"}",
            occurred_on: record[:date],
            amount: record[:amount],
            raw_description: record[:description],
            raw: {"Data" => record[:date].strftime("%d/%m/%Y"), "Valor" => record[:amount].to_d.to_s("F"),
                  "Identificador" => record[:id], "Descrição" => record[:description]},
            **fields
          )
        end

        [rows, warnings]
      end

      # @return [Hash] kind, description, and counterparty / counter_account when known
      def classify(description, amount)
        by_sign = amount.negative? ? "purchase" : "income"

        if (account = TRANSFERS[description])
          {kind: "transfer", description:, counter_account: account}
        elsif description.start_with?(CARD_TOP_UP)
          {kind: "transfer", description: "Pix no Crédito (valor adicionado pelo cartão)", counter_account: ACCOUNT}
        elsif (rest = strip_prefix(description, PIX_OUT, PIX_IN, TRANSFER_IN, PIX_REFUND))
          # Some transfers name the sender with no document or bank ("NAME S.A.").
          party = party(rest) || {name: rest}
          kind = description.start_with?(PIX_REFUND) ? "refund" : by_sign
          {kind:, description: party[:name], counterparty: party}
        elsif (name = strip_prefix(description, BOLETO))
          {kind: "bill_payment", description: name, counterparty: {name:}}
        elsif (name = strip_prefix(description, NUPAY, DEBIT))
          {kind: by_sign, description: name, counterparty: {name:}}
        elsif description == PHONE_TOP_UP
          {kind: by_sign, description:, counterparty: {name: description}}
        else
          {kind: by_sign, description:, unparsed: true}
        end
      end

      def strip_prefix(text, *prefixes)
        prefix = prefixes.find { text.start_with?(_1) }
        text.delete_prefix(prefix).strip if prefix
      end

      def party(text)
        match = PARTY.match(text) or return nil
        document = match[:document]
        party = {
          name: match[:name].strip,
          document:,
          document_kind: document.start_with?("•") ? "cpf_masked" : "cnpj"
        }

        if match[:bank] && (bank = BANK.match(match[:bank].strip))
          party.merge!(
            bank_name: bank[:bank_name].to_s.strip.then { _1.empty? ? nil : _1 },
            bank_code: bank[:bank_code],
            branch: bank[:branch],
            account_number: bank[:account_number]
          )
        end

        party
      end

      def period(file_name, rows, warnings)
        if (match = PERIOD.match(File.basename(file_name.to_s)))
          from = Date.new(match[3].to_i, MONTHS.index(match[2]) + 1, match[1].to_i)
          to = Date.new(match[6].to_i, MONTHS.index(match[5]) + 1, match[4].to_i)
          outside = rows.count { !(from..to).cover?(_1.occurred_on) }
          raise Error.new(:rows_outside_period, rows: outside) if outside.positive?

          [from, to]
        elsif rows.any?
          warnings << Notice[:no_period_in_name]
          rows.map(&:occurred_on).minmax
        else
          raise Error.new(:no_rows_no_period)
        end
      rescue Date::Error
        raise Error.new(:invalid_period)
      end
    end
  end
end
