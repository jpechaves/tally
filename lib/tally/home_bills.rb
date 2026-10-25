# frozen_string_literal: true

module Tally
  # Home bills (issue #113, docs/architecture.md, section 8.9): rent, energy, water,
  # internet, each due on a day of the month. A month is paid once a payment is linked to
  # an imported row or entered by hand; until its due day it is due, after that late.
  module HomeBills
    # Rows this many days either side of the due day can pay it.
    WINDOW_DAYS = 15
    # Without a payee, a row pays the bill when its amount is this close to the expected one.
    TOLERANCE_PCT = 20
    Month = Data.define(:month, :due_on, :status, :payment)

    module_function

    # "2026-02", 31 -> "2026-02-28"
    def due_on(month, day)
      first = Date.new(month[0, 4].to_i, month[5, 2].to_i, 1)
      (first + ([day, first.next_month.prev_day.day].min - 1)).iso8601
    end

    # The month before and this one, the months the pages show.
    def months(today) = [today.prev_month.strftime("%Y-%m"), today.strftime("%Y-%m")]

    def status(bill, month, payment, today:)
      return :paid if payment

      (today.iso8601 <= due_on(month, bill[:due_day])) ? :due : :late
    end

    # @param payments [Hash] [bill id, month] => payment (HomeBillRepo#payments)
    # @return [Array<Month>]
    def status_by_month(bill, months, payments, today:)
      months.map do |month|
        payment = payments[[bill[:id], month]]
        Month.new(month:, due_on: due_on(month, bill[:due_day]), status: status(bill, month, payment, today:), payment:)
      end
    end

    # Spending rows of the bill's own month or near its due day, to pick the payment from:
    # the month's own first, then nearest the due day. A bill due on the 31st and paid on
    # the 8th is still that month's.
    # @param rows [Array<Hash>] InsightRepo#rows
    def candidates(bill, month, rows)
      due = Date.iso8601(due_on(month, bill[:due_day]))
      rows.filter_map do |row|
        days = (Date.iso8601(row[:occurred_on]) - due).abs
        own = row[:occurred_on].start_with?(month)
        [[own ? 0 : 1, days], row] if row[:amount_cents].negative? && (own || days <= WINDOW_DAYS)
      end.sort_by(&:first).map(&:last)
    end

    # The row that most likely paid the month: the payee's first candidate; without a
    # payee, one of its category (if it has one) near the expected amount.
    def suggest(bill, month, rows)
      near = candidates(bill, month, rows)
      return near.find { Insights.payee_key(_1) == bill[:payee_key] } if bill[:payee_key]

      expected = bill[:expected_cents]
      return unless expected

      near.select { (!bill[:category_id] || _1[:category_id] == bill[:category_id]) && close?(-_1[:amount_cents], expected) }
        .min_by { (-_1[:amount_cents] - expected).abs }
    end

    def close?(cents, expected) = (cents - expected).abs * 100 <= expected * TOLERANCE_PCT
  end
end
