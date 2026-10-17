# frozen_string_literal: true

require "bigdecimal"

module Tally
  # Transfers between accounts in different currencies: a Conta Global top-up is US$ 178,74
  # there and R$ 1.000,00 in Nubank conta. The two legs can't sum to zero, so they are
  # matched through the rate the dollar leg prints (docs/architecture.md, section 6).
  module Exchange
    # How far the other leg may be from the dollar amount at the printed rate. The BRL leg
    # also pays IOF (3,5% in 2026) and the bank's rounding, so it costs a bit more.
    RATIO = (BigDecimal("0.98")..BigDecimal("1.08"))

    module_function

    # Whether two transfer legs, in accounts of these currencies, are the same money.
    #
    # @param a, b [Hash] transaction rows (amount_cents, exchange_currency, exchange_rate)
    # @param currency_a, currency_b [String] their accounts' currencies
    def legs?(a, b, currency_a, currency_b)
      return a[:amount_cents] == -b[:amount_cents] if currency_a == currency_b
      return false unless a[:amount_cents].negative? != b[:amount_cents].negative?

      if a[:exchange_rate] && a[:exchange_currency] == currency_b
        converted?(a, b)
      elsif b[:exchange_rate] && b[:exchange_currency] == currency_a
        converted?(b, a)
      else
        false
      end
    end

    # The leg with the rate, converted, against the other leg's amount.
    def converted?(priced, other)
      expected = BigDecimal(priced[:amount_cents].abs) * BigDecimal(priced[:exchange_rate])
      RATIO.cover?(BigDecimal(other[:amount_cents].abs) / expected)
    end
  end
end
