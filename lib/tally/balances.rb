# frozen_string_literal: true

module Tally
  # An account's balance, anchored on what the bank showed (balance checks). Without a
  # check it is the sum of the account's rows from zero, which misses whatever was there
  # before the first imported statement. With checks, it is the newest one plus the rows
  # dated after it, and each later check says whether the rows since the one before add up.
  module Balances
    Check = Data.define(:id, :checked_on, :balance_cents, :difference_cents)
    Balance = Data.define(:balance_cents, :checks) do
      def last_check = checks.last
    end

    module_function

    # @param checks [Array<Hash>] the account's checks, oldest first (BalanceCheckRepo#by_account)
    # @param days [Hash{String => Integer}] the sum of the account's rows on each day
    def call(checks, days)
      return Balance.new(balance_cents: days.values.sum, checks: []) if checks.empty?

      previous = nil
      checked = checks.map do |check|
        difference = previous && (check[:balance_cents] - previous[:balance_cents] - between(days, previous[:checked_on], check[:checked_on]))
        previous = check
        Check.new(id: check[:id], checked_on: check[:checked_on], balance_cents: check[:balance_cents], difference_cents: difference)
      end
      last = checks.last
      Balance.new(balance_cents: last[:balance_cents] + between(days, last[:checked_on], nil), checks: checked)
    end

    # The rows dated after `from` and up to `through` (nil for no end).
    def between(days, from, through) = days.sum { |day, cents| (day > from && (through.nil? || day <= through)) ? cents : 0 }
  end
end
