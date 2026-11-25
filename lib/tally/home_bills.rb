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

    # How many months the pages show (the ?months= choice): this one, the one before too
    # (the default), the last six, or every month since the first imported row.
    SPANS = %w[1 2 6 all].freeze
    DEFAULT_SPAN = "2"

    def span(param) = SPANS.include?(param.to_s) ? param.to_s : DEFAULT_SPAN

    # The months the charts show: the last twelve through this one, from the first
    # imported row on.
    def chart_months(today, first:) = months(today, "12").select { first.nil? || _1 >= first }

    # What was paid toward a bill each month, two ways. By the bill's month: its payment
    # (linked, by hand or found, see with_found), whatever day it was made. By date: what
    # was paid in each month, so a month with two payments shows both. Either way, plus any
    # other spending with its payee in the month it was made (an extra or early installment).
    # @param rows [Array<Hash>] InsightRepo#rows over the months, without the rows payments link
    # @param payments [Hash] [bill id, month] => payment (HomeBillRepo#payments)
    # @return [Hash] :bill_month and :by_date, cents for each month, nil when nothing was paid
    def paid_by_month(bill, months, rows, payments)
      paid = with_found(bill, months, rows, payments).filter_map { |(id, month), payment| [month, payment] if id == bill[:id] }
      extra = extra_spending(bill, rows, paid.filter_map { _2[:row_id] })
      {bill_month: sums(months, paid.map { [_1, _2[:amount_cents]] } + extra),
       by_date: gapless(sums(months, paid.map { [_2[:paid_on][0, 7], _2[:amount_cents]] } + extra))}
    end

    # [[month, cents]] spent with the payee besides the payments' rows (ids).
    def extra_spending(bill, rows, ids)
      payee_spending(bill, rows).reject { ids.include?(_1[:id]) }.map { [_1[:occurred_on][0, 7], -_1[:amount_cents]] }
    end

    # paid_by_month for all the bills together.
    def chart(bills, months, rows, payments)
      paid = bills.map { paid_by_month(_1, months, rows, payments) }
      %i[bill_month by_date].to_h { |key| [key, paid.map { _1[key] }.transpose.map { _1.compact.sum if _1.any? }] }
    end

    # The spending rows with the bill's payee; none without one.
    def payee_spending(bill, rows)
      key = bill[:payee_key]
      key ? rows.select { _1[:amount_cents].negative? && Insights.payee_key(_1) == key } : []
    end

    # [[month, cents]] -> cents for each month, nil when none
    def sums(months, amounts)
      totals = amounts.group_by(&:first).transform_values { _1.sum(&:last) }
      months.map { totals[_1] }
    end

    # A month between two payments with none made in it paid nothing: 0, so the line goes on.
    def gapless(cents)
      first, last = cents.index { _1 }, cents.rindex { _1 }
      cents.each_with_index.map { |value, index| (first && index.between?(first, last)) ? value.to_i : value }
    end

    # A bill's page, keeping a span other than the default.
    def path(id, span = DEFAULT_SPAN) = (span == DEFAULT_SPAN) ? "/home-bills/#{id}" : "/home-bills/#{id}?months=#{span}"

    # The months a span shows, oldest first, through this month.
    # @param first [String, nil] the oldest month with rows, for "all"
    def months(today, span = DEFAULT_SPAN, first: nil)
      last = Date.new(today.year, today.month, 1)
      start = if span == "all"
        first ? [Date.iso8601("#{first}-01"), last].min : last
      else
        last << (span.to_i - 1)
      end
      (0..).lazy.map { start >> _1 }.take_while { _1 <= last }.map { _1.strftime("%Y-%m") }.to_a
    end

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

    # The payments, plus the months nothing is linked to yet that a row surely paid: its
    # payee's (the chart counts them too) or, without a payee, one of exactly the expected
    # amount. Found, not saved: the bill's page asks to save it. A row pays one month only.
    # @param rows [Array<Hash>] InsightRepo#rows, without the rows payments link
    def with_found(bill, months, rows, payments)
      months.each_with_object(payments.dup) do |month, all|
        next if all[[bill[:id], month]]

        row = suggest(bill, month, rows)
        next if row.nil? || (!bill[:payee_key] && -row[:amount_cents] != bill[:expected_cents])

        rows -= [row]
        all[[bill[:id], month]] = {paid_on: row[:occurred_on], amount_cents: -row[:amount_cents], account_name: row[:account_name], row_id: row[:id], found: true}
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
