# frozen_string_literal: true

module Tally
  # What the money in a foreign-currency account cost in reais (issue #22): Conta Global is
  # topped up from Nubank conta, and each top-up's two legs say how many reais bought how
  # many dollars, IOF and spread included.
  module TopUps
    # Dollars bought (cents) and the reais paid for them (paid_cents), both positive.
    Cost = Data.define(:cents, :paid_cents) do
      # Reais per dollar, exact.
      def rate = Rational(paid_cents, cents)

      # An amount of this account's money in reais at this cost, rounded half away from zero.
      def convert(amount_cents) = (amount_cents * rate).round
    end

    module_function

    # @param row [Hash] a row from TransactionRepo#top_ups
    # @return [Cost, nil] nil when the reais leg isn't paired yet
    def cost_of(row)
      return unless row[:other_cents] && row[:other_currency] == Money::DEFAULT_CURRENCY

      Cost.new(cents: row[:amount_cents], paid_cents: -row[:other_cents])
    end

    # The average cost of every paired top-up in `rows`: total reais over total dollars.
    # @return [Cost, nil] nil when none is paired
    def average(rows)
      costs = rows.filter_map { cost_of(_1) }
      return if costs.empty?

      Cost.new(cents: costs.sum(&:cents), paid_cents: costs.sum(&:paid_cents))
    end
  end
end
