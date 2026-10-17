# frozen_string_literal: true

require "date"
require "digest"

module Tally
  # Statement parsers. Each one turns a file into a {Statement}: plain data, no database.
  # Writing it (upsert, transfers, import history) is ImportStatement's job.
  # Formats and their quirks are in docs/statement-import.md.
  module Importers
    # The file can't be read as this format, or it fails a check (e.g. totals that don't
    # match the bill). Nothing from it is written.
    class Error < StandardError; end

    # What a parser returns.
    #
    # - source: "nubank_account_csv" | "nubank_card_csv" | "itau_card_pdf" | "conta_global_csv"
    # - account_name: the account the rows belong to (one of {ACCOUNTS})
    # - period_start, period_end: the dates the file covers; on re-import, rows of this
    #   account in that range (or on this bill) that are missing from the file get flagged
    # - card_statement: the bill's figures (card sources only): due_on, closing_on and *_cents
    # - warnings: things worth showing that don't stop the import
    Statement = Data.define(
      :source, :account_name, :period_start, :period_end, :rows, :card_statement, :warnings
    ) do
      def initialize(card_statement: nil, warnings: [], **rest)
        super(card_statement:, warnings:, **rest)
      end
    end

    # One transaction, signed from its account's point of view (negative = money out).
    #
    # - external_id: the upsert key within the account (docs/statement-import.md, section 4)
    # - occurred_on: the date that counts for reports; purchased_on: the original purchase
    #   date, when it differs (card installments)
    # - kind: purchase | refund | fee | income | transfer | bill_payment
    # - counterparty: who the money went to or came from, as a Hash (name, document,
    #   document_kind, bank_name, bank_code, branch, account_number), or nil
    # - counter_account: for transfers, the name of the other account (one of {ACCOUNTS})
    # - exchange_amount: the other side of a currency exchange, as Money in its currency
    #   (41,20 GBP for a card purchase in London), or nil; exchange_currency names that
    #   currency even when the statement doesn't print the amount (a top-up from BRL)
    # - exchange_rate: units of exchange_currency per one unit of the row's currency, as
    #   decimal text, or nil
    # - fee: the bank's fee as Money in the row's currency, already inside amount, or nil
    # - raw: the source row's own fields, stored as raw_json for audit
    Row = Data.define(
      :external_id, :occurred_on, :purchased_on, :amount, :kind, :description, :raw_description,
      :bank_category, :location, :installment_number, :installment_total, :purchase_key,
      :counterparty, :counter_account, :exchange_currency, :exchange_amount, :exchange_rate, :fee, :raw
    ) do
      def initialize(purchased_on: nil, bank_category: nil, location: nil, installment_number: nil,
        installment_total: nil, purchase_key: nil, counterparty: nil, counter_account: nil,
        exchange_currency: nil, exchange_amount: nil, exchange_rate: nil, fee: nil, **rest)
        super(purchased_on:, bank_category:, location:, installment_number:, installment_total:,
          purchase_key:, counterparty:, counter_account:, exchange_currency:, exchange_amount:,
          exchange_rate:, fee:, **rest)
      end
    end

    # The accounts the importers know, created on first use.
    #
    # mirror_transfers: the account has no statement of its own, so each transfer into or
    # out of it is mirrored there, and its balance stays right (architecture.md, section 6).
    ACCOUNTS = {
      "Nubank conta" => {kind: "checking", institution: "nubank"},
      "Nubank cartão" => {kind: "credit_card", institution: "nubank"},
      "Itaú cartão" => {kind: "credit_card", institution: "itau"},
      "Itaú conta" => {kind: "checking", institution: "itau", mirror_transfers: 1},
      "Nubank RDB" => {kind: "investment", institution: "nubank", mirror_transfers: 1},
      # A dollar account: the conversion leaves BRL, so there is nothing to mirror in BRL.
      "Nubank Conta Global" => {kind: "checking", institution: "nubank", currency: "USD"}
    }.freeze

    SOURCES = {
      "nubank_account_csv" => "Nubank conta (CSV)",
      "nubank_card_csv" => "Nubank cartão (CSV)",
      "itau_card_pdf" => "Itaú cartão (PDF)",
      "conta_global_csv" => "Nubank Conta Global (CSV)"
    }.freeze

    # Picks the parser for a file from its first bytes.
    #
    # @return [#call] a parser instance; `parser.call(file_name, content)` returns a {Statement}
    # @raise [Error] for a file no parser recognizes
    def self.for(content)
      head = content.byteslice(0, 64).to_s.b.delete_prefix("\xEF\xBB\xBF".b)

      if head.start_with?("%PDF")
        ItauCardPdf.new
      elsif head.start_with?(NubankAccountCSV::HEADER.b)
        NubankAccountCSV.new
      elsif head.start_with?(NubankCardCSV::HEADER.b)
        NubankCardCSV.new
      elsif head.start_with?(ContaGlobalCSV::HEADER_START.b)
        ContaGlobalCSV.new
      else
        raise Error, "unknown file format: expected a Nubank account CSV, a Nubank card CSV, " \
          "a Conta Global CSV or an Itaú bill PDF"
      end
    end

    # A Pix to or from a counterparty marked as you is a transfer. When the bank is one
    # Tally knows, this names your account there.
    #
    # @param counterparty [#[]] with :bank_code and :bank_name
    # @return [String, nil] one of {ACCOUNTS}, or nil for a one-leg transfer
    def self.self_account_for(counterparty)
      if counterparty[:bank_code].to_s.rjust(4, "0") == "0341" || counterparty[:bank_name].to_s.match?(/\bITA[UÚ]\b/i)
        "Itaú conta"
      end
    end

    # Reads a file's bytes and returns its {Statement}.
    def self.parse(file_name, content)
      self.for(content).call(file_name, content)
    end

    # A short stable key from the parts that identify a row.
    def self.digest(*parts)
      Digest::SHA256.hexdigest(parts.map(&:to_s).join("|"))[0, 32]
    end

    # Numbers identical rows: the k-th repeat of the same identity gets k (0, 1, 2, ...), so
    # two truly identical charges in one bill stay two rows (docs/statement-import.md, 2b).
    class Repeats
      def initialize
        @seen = Hash.new(0)
      end

      def next(*identity)
        k = @seen[identity]
        @seen[identity] += 1
        k
      end
    end

    # Text helpers shared by the parsers.
    module Text
      module_function

      # Reads the file as UTF-8 and drops a byte-order mark.
      def utf8(content)
        text = content.dup.force_encoding(Encoding::UTF_8)
        raise Error, "the file is not valid UTF-8" unless text.valid_encoding?

        text.delete_prefix("﻿")
      end

      def date(text, format, line)
        Date.strptime(text, format)
      rescue Date::Error, TypeError
        raise Error, "line #{line}: not a date: #{text.inspect}"
      end
    end
  end
end
