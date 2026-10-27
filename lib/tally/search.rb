# frozen_string_literal: true

module Tally
  # Finding a name the way you would type it: without accents, ignoring case, and with any
  # run of spaces or punctuation as one space ("joao silva" finds "JOÃO  DA-SILVA" only as
  # "joao da silva"; "joao" or "silva" find it too).
  #
  # SQLite's own LIKE folds ASCII case only, so the database gets FUNCTION, which folds a
  # column the same way the query is folded here.
  module Search
    FUNCTION = "tally_fold"

    module_function

    # "João  da-Silva" -> "JOAO DA SILVA"
    def fold(text)
      text&.unicode_normalize(:nfkd)&.gsub(/\p{Mn}/, "")&.upcase&.gsub(/[^A-Z0-9]+/, " ")&.strip
    end

    # A condition that the column, folded, holds this folded text. Folded text is only
    # letters, digits and spaces, so there is nothing in it for LIKE to escape.
    def like(column, folded) = Sequel.like(Sequel.function(FUNCTION, column), "%#{folded}%")

    # A search read as an amount, when all of it is one: "45,90", "45.90", "1.234,56",
    # "R$ 45,90", "-45,90" (decimal comma or point, an optional R$ or US$). The sign is -1
    # or 1 only when typed, nil for either.
    # @return [Array(Integer, Integer), nil] [sign, cents], nil when it isn't an amount
    def amount(text)
      match = /\A(?<sign>[+-]?)(?:US\$|R\$)?(?<number>[\d.,]+)\z/.match(text.to_s.gsub(/[[:space:]]+/, ""))
      return unless match

      cents = Money::SEPARATORS.keys.lazy.filter_map { |decimal| parse_cents(match[:number], decimal) }.first
      [{"-" => -1, "+" => 1}[match[:sign]], cents] if cents
    end

    def parse_cents(number, decimal)
      Money.parse(number, decimal:).cents
    rescue Money::ParseError
      nil
    end
    private_class_method :parse_cents

    # Adds FUNCTION to a new SQLite connection (config/providers/db.rb).
    def register(connection)
      SqlFunction.define(connection, FUNCTION, 1) { fold(_1) }
    end
  end
end
