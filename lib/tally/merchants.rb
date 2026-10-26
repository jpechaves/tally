# frozen_string_literal: true

module Tally
  # Card statements name a merchant with codes that change from one purchase to the next
  # ("LOJA EXEMPLO*AB12", "LOJA EXEMPLO*CD34", "FARMACIA EXEMPLO 0123"), and each bank cuts
  # long names at its own length ("PADARIA EXEMPLO CENT" and "Padaria Exemplo Centro").
  # These reduce a name to the part that stays the same, so the variants are one counterparty.
  module Merchants
    # Payment processors that put their own prefix before the merchant ("PAG*LOJA EXEMPLO").
    FACILITATORS = %w[PAG PG PAGS MP MERCADOPAGO EC IFD DL EBN EBANX PAYPAL PICPAY SUMUP ZP HTM].freeze

    # Shortest key that may match a longer one cut by another bank, so short generic names
    # ("PADARIA") don't swallow others.
    MIN_PREFIX = 8

    module_function

    # "LOJA EXEMPLO*AB12" -> "LOJA EXEMPLO"; "PAG*Loja Exemplo" -> "Loja Exemplo";
    # "FARMACIA EXEMPLO 0123" -> "FARMACIA EXEMPLO"; "TURISMO B" -> "TURISMO" (a card's
    # one-letter suffix)
    def stable_name(name)
      name = name.strip.squeeze(" ")
      head, tail = name.split("*", 2).map(&:strip)
      if tail && !tail.empty? && FACILITATORS.include?(fold(head)) then name = tail
      elsif head && !head.empty? then name = head
      end
      words = name.split
      words.pop while words.size > 1 && (words.last.match?(/\d/) || words.last.length == 1)
      words.join(" ")
    end

    # Upper case letters and digits only, without accents: "Café Exemplo" -> "CAFEEXEMPLO".
    def key(name)
      folded = fold(stable_name(name))
      folded.empty? ? name.strip.upcase : folded
    end

    def fold(text) = text.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").upcase.gsub(/[^A-Z0-9]/, "")

    # #key for SQL, as KEY_FUNCTION(name), so a card merchant finds the same company paid
    # by Pix or boleto, which has a CNPJ (CounterpartyRepo).
    KEY_FUNCTION = "tally_merchant_key"

    # Adds KEY_FUNCTION to a new SQLite connection (config/providers/db.rb).
    def register(connection)
      SqlFunction.define(connection, KEY_FUNCTION, 1) { key(_1.to_s) }
    end
  end
end
