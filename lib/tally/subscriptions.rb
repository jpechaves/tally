# frozen_string_literal: true

module Tally
  # Charges that repeat every month (issue #74, docs/architecture.md, section 8.7):
  # streaming, phone plan, insurance, apps, gym. The easiest place to look for cuts.
  #
  # A payee (Insights.payee_key, so a card merchant and its Pix or boleto payments are one)
  # is a subscription when, in some 4 months in a row, it charged in at least 3, each
  # month's total within 10% of their typical (median) amount, the latest one allowed to be
  # a price increase. A foreign charge counts
  # with its IOF row, which has the same merchant, so the rate moving doesn't break it.
  # Installments are left out, and so are fees without a merchant (the card's own fee).
  class Subscriptions
    Item = Data.define(:key, :payee, :category_name, :accounts, :last_cents, :last_on, :first_month,
      :increase_cents, :stopped, :manual, :ids) do
      # What it costs a month: its latest charge.
      def monthly_cents = last_cents

      def yearly_cents = monthly_cents * 12
    end

    WINDOW = 4
    MIN_MONTHS = 3
    TOLERANCE_PCT = 10
    # Months without a charge before a subscription counts as stopped.
    STOPPED_MONTHS = 2

    attr_reader :items

    # @param rows [Array<Hash>] InsightRepo#rows, any months
    # @param month [String] "YYYY-MM", the last month looked at
    # @param dismissed [Enumerable<String>] payee keys you said aren't subscriptions
    # @param marked [Enumerable<String>] payee keys you said are, found or not
    def initialize(rows, month:, dismissed: [], marked: [])
      @month = month
      @marked = marked.to_set
      charges = rows.select { charge?(_1) && Insights.month_of(_1) <= month }
      @items = charges.group_by { Insights.payee_key(_1) }.filter_map do |key, payee_rows|
        next if dismissed.include?(key)

        item(key, payee_rows)
      end.sort_by { [_1.stopped ? 1 : 0, -_1.monthly_cents, _1.payee] }
    end

    def monthly_cents = items.reject(&:stopped).sum(&:monthly_cents)

    def yearly_cents = monthly_cents * 12

    private

    def charge?(row)
      Insights.spending?(row) && row[:installment_total].nil? && (row[:kind] != "fee" || row[:counterparty_id])
    end

    def item(key, rows)
      totals = rows.group_by { Insights.month_of(_1) }.transform_values { Insights.spent_cents(_1) }
        .select { |_, cents| cents.positive? }.sort.to_h
      manual = @marked.include?(key)
      return if totals.empty? || !(manual || repeats?(totals))

      months = totals.keys
      last = rows.select { Insights.month_of(_1) == months.last }.max_by { _1[:occurred_on] }
      Item.new(
        key:, payee: Insights.payee_label(last), category_name: last[:category_name],
        accounts: rows.map { _1[:account_name] }.uniq, last_cents: totals[months.last], last_on: last[:occurred_on],
        first_month: months.first, increase_cents: increase(totals.values.last(3)),
        stopped: Insights.months_between(months.last, @month) >= STOPPED_MONTHS, manual:, ids: rows.map { _1[:id] }
      )
    end

    # Some WINDOW months in a row with MIN_MONTHS charges near their median, or all but the
    # latest near it and the latest a price increase (so three charges with a rise count).
    def repeats?(totals)
      first = totals.keys.first
      ([first] + Insights.next_months(first, Insights.months_between(first, @month))).any? do |last|
        window = Insights.previous_months(last, WINDOW - 1) + [last]
        values = totals.values_at(*window).compact
        values.size >= MIN_MONTHS && (near_typical?(values) || (increase(values.last(3)) && near_typical?(values[...-1])))
      end
    end

    def near_typical?(values)
      typical = values.sort[values.size / 2]
      values.all? { (_1 - typical).abs * 100 <= typical * TOLERANCE_PCT }
    end

    # How much the latest charge went up from the one before: any rise on a fixed price
    # (the two before it equal), or over 10% on one that varies (a foreign currency).
    def increase(values)
      *before, previous, last = [nil, nil] + values
      rise = last - previous if previous && last > previous
      rise if rise && (before.last == previous || rise * 100 > previous * TOLERANCE_PCT)
    end
  end
end
