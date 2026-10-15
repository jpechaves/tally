# frozen_string_literal: true

require "bigdecimal"

module Tally
  # An exact amount of money: whole cents (centavos) plus a currency code.
  #
  # Every amount in Tally travels as a Money. The rules (docs/architecture.md, section 5):
  #
  # - Cents are always an Integer. Floats are refused, so rounding errors can't creep in.
  # - Arithmetic is integer-only, and mixing currencies raises instead of guessing.
  # - Text is parsed once, at the edges (statements, forms), with BigDecimal. More than two
  #   decimal places is an error, never silently rounded.
  # - Splitting uses {#allocate} (largest remainder), so the parts always add back up to the
  #   total, to the cent.
  #
  # Signs follow the ledger convention: negative is money leaving an account, positive is
  # money coming in.
  class Money
    include Comparable

    class Error < StandardError; end

    # Raised when two amounts in different currencies are combined or compared.
    class CurrencyMismatch < Error; end

    # Raised when text can't be read as an exact amount.
    class ParseError < Error; end

    DEFAULT_CURRENCY = "BRL"

    SYMBOLS = {"BRL" => "R$"}.freeze

    SEPARATORS = {
      # decimal mark => thousands separator
      "," => ".",
      "." => ","
    }.freeze

    # The decimal mark each supported locale writes (Tally::Locales).
    DECIMAL_MARKS = {"pt-BR" => ",", "en" => "."}.freeze

    # The decimal mark for a locale; Brazilian for anything unknown.
    def self.decimal_mark(locale) = DECIMAL_MARKS.fetch(locale.to_s, ",")

    attr_reader :cents, :currency

    # @param cents [Integer] whole cents, signed
    # @param currency [String] ISO 4217 code, e.g. "BRL"
    def initialize(cents, currency = DEFAULT_CURRENCY)
      unless cents.is_a?(Integer)
        raise TypeError, "Money needs whole Integer cents, got #{cents.inspect} (#{cents.class})"
      end

      unless currency.is_a?(String) && currency.match?(/\A[A-Z]{3}\z/)
        raise ArgumentError, "currency must be a 3-letter ISO code, got #{currency.inspect}"
      end

      @cents = cents
      @currency = currency.dup.freeze
      freeze
    end

    def self.zero(currency = DEFAULT_CURRENCY)
      new(0, currency)
    end

    # Parses an amount written as text.
    #
    # @param input [String] e.g. "1.234,56", "- 7,06", "R$ 12,90" (decimal: ",")
    #   or "-518.54", "1,234.56" (decimal: ".")
    # @param decimal [String] the decimal mark the source uses: "," (Brazilian, the default)
    #   or "."; the other character is accepted as a thousands separator, in groups of three
    # @raise [ParseError] for anything that isn't an exact amount with at most 2 decimals
    def self.parse(input, currency: DEFAULT_CURRENCY, decimal: ",")
      thousands = SEPARATORS.fetch(decimal) do
        raise ArgumentError, "decimal must be \",\" or \".\", got #{decimal.inspect}"
      end
      raise ParseError, "expected text, got #{input.inspect}" unless input.is_a?(String)

      # Statements write negatives as "- 7,06" and prefix "R$", so drop spaces and the symbol.
      text = input.gsub(/[[:space:]]+/, "").sub("R$", "")

      dec = Regexp.escape(decimal)
      sep = Regexp.escape(thousands)
      match = /\A(?<sign>[+-]?)(?<int>\d{1,3}(?:#{sep}\d{3})+|\d+)(?:#{dec}(?<frac>\d+))?\z/.match(text)
      raise ParseError, "not an amount: #{input.inspect}" unless match

      frac = match[:frac].to_s
      if frac.length > 2
        raise ParseError, "more than 2 decimal places in #{input.inspect}; refusing to round"
      end

      value = BigDecimal("#{match[:sign]}#{match[:int].delete(thousands)}.#{frac.ljust(2, "0")}")
      new((value * 100).to_i, currency)
    end

    # Adds up a list of Money, all in the given currency. An empty list is zero.
    def self.sum(amounts, currency = DEFAULT_CURRENCY)
      amounts.reduce(zero(currency)) { |total, amount| total + amount }
    end

    def +(other)
      self.class.new(cents + same_currency!(other).cents, currency)
    end

    def -(other)
      self.class.new(cents - same_currency!(other).cents, currency)
    end

    def -@
      self.class.new(-cents, currency)
    end

    # Multiplies by a whole number (e.g. installment count). Fractions go through {#allocate}.
    def *(other)
      unless other.is_a?(Integer)
        raise TypeError, "Money can only be multiplied by an Integer; use #allocate to divide"
      end

      self.class.new(cents * other, currency)
    end

    def abs
      self.class.new(cents.abs, currency)
    end

    def zero? = cents.zero?

    def positive? = cents.positive?

    def negative? = cents.negative?

    def <=>(other)
      return nil unless other.is_a?(Money)

      cents <=> same_currency!(other).cents
    end

    # Equal when cents and currency match. Unlike <=>, comparing currencies for equality is
    # allowed and simply false.
    def ==(other)
      other.is_a?(Money) && cents == other.cents && currency == other.currency
    end
    alias_method :eql?, :==

    def hash
      [self.class, cents, currency].hash
    end

    # Splits the amount in proportion to the given weights, using the largest remainder
    # method: each part gets its rounded-down share, and the leftover cents go one at a time
    # to the parts with the largest fractional remainders (earliest part wins a tie).
    # The parts always add up to exactly this amount.
    #
    # @param weights [Array<Integer>] non-negative, at least one positive
    # @return [Array<Money>] one part per weight, same sign as this amount
    #
    # @example
    #   Money.new(100).allocate([1, 1, 1]).map(&:cents) # => [34, 33, 33]
    def allocate(weights)
      unless weights.is_a?(Array) && weights.any? && weights.all? { _1.is_a?(Integer) && _1 >= 0 }
        raise ArgumentError, "weights must be a non-empty array of non-negative Integers"
      end

      total_weight = weights.sum
      raise ArgumentError, "at least one weight must be positive" if total_weight.zero?

      amount = cents.abs
      shares = weights.map { |weight| (amount * weight).divmod(total_weight) }
      leftover = amount - shares.sum(&:first)

      bonus = shares.each_with_index
        .sort_by { |(_, remainder), index| [-remainder, index] }
        .first(leftover)
        .to_h { |_, index| [index, 1] }

      sign = cents.negative? ? -1 : 1
      shares.each_with_index.map do |(share, _), index|
        self.class.new(sign * (share + bonus.fetch(index, 0)), currency)
      end
    end

    # Splits into n parts that differ by at most one cent.
    def split(parts)
      raise ArgumentError, "parts must be a positive Integer" unless parts.is_a?(Integer) && parts.positive?

      allocate([1] * parts)
    end

    # The exact amount as a BigDecimal, e.g. for display or export. Never for arithmetic.
    def to_d
      BigDecimal(cents) / 100
    end

    # "R$ 1.234,56", "-R$ 7,06" in Portuguese (the default); "R$ 1,234.56" in English.
    # Other currencies use their code.
    def format(locale = "pt-BR")
      decimal = self.class.decimal_mark(locale)
      units, rest = cents.abs.divmod(100)
      grouped = units.to_s.reverse.scan(/\d{1,3}/).join(SEPARATORS.fetch(decimal)).reverse
      "#{"-" if negative?}#{SYMBOLS.fetch(currency, currency)} #{grouped}#{decimal}#{rest.to_s.rjust(2, "0")}"
    end

    def to_s = format

    # "1234,56" (or "1234.56" in English): for a form field, without symbol or grouping,
    # so .parse reads it back exactly.
    def to_field(locale = "pt-BR")
      units, rest = cents.abs.divmod(100)
      "#{"-" if negative?}#{units}#{self.class.decimal_mark(locale)}#{rest.to_s.rjust(2, "0")}"
    end

    def inspect
      "#<#{self.class.name} #{format}>"
    end

    private

    def same_currency!(other)
      raise TypeError, "expected Money, got #{other.inspect}" unless other.is_a?(Money)

      unless other.currency == currency
        raise CurrencyMismatch, "can't combine #{currency} with #{other.currency}"
      end

      other
    end
  end
end
