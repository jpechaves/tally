# frozen_string_literal: true

module Tally
  # Where the money went in one month (docs/architecture.md, section 8.2): income,
  # spending and what was saved next to the 3-month average, spending by category and by
  # nature, top payees, and how much of the month was card installments.
  class Report
    AVERAGE_MONTHS = 3

    Line = Data.define(:id, :name, :cents, :average_cents, :share, :rows, :children) do
      # Change against the average, in percent; nil without an average.
      def change = average_cents.zero? ? nil : ((cents - average_cents) * 100.0 / average_cents.abs).round(1)
    end

    attr_reader :month, :baseline_months

    # @param rows [Array<Hash>] rows of `month` and the months before it
    def initialize(rows, month:)
      @month = month
      @baseline_months = Insights.previous_months(month, AVERAGE_MONTHS)
      by_month = rows.group_by { Insights.month_of(_1) }
      @rows = by_month.fetch(month, [])
      @baseline = @baseline_months.select { by_month.key?(_1) }.to_h { [_1, by_month[_1]] }
    end

    # The months before this one that have rows; the averages use only these. Empty when
    # none has, whether or not those months were imported.
    def averaged_months = @baseline.keys

    def income_cents = Insights.income_cents(@rows)

    def spending_cents = Insights.spent_cents(@rows)

    def saved_cents = income_cents - spending_cents

    def average_income_cents = Insights.average(@baseline.values.map { Insights.income_cents(_1) })

    def average_spending_cents = Insights.average(@baseline.values.map { Insights.spent_cents(_1) })

    def average_saved_cents = average_income_cents - average_spending_cents

    def spending_rows = @rows.select { Insights.spending?(_1) }

    # Parent categories, biggest first, each with its categories. Rows with no category
    # make a line with a nil id and name.
    def categories
      top = spending_rows.group_by { [_1[:parent_id] || _1[:category_id], _1[:parent_name] || _1[:category_name]] }
      lines = top.map do |(id, name), rows|
        children = rows.select { _1[:parent_id] }.group_by { [_1[:category_id], _1[:category_name]] }
          .map { |(child_id, child_name), child_rows| line(child_id, child_name, child_rows) { _1[:category_id] == child_id } }
        line(id, name, rows, children.sort_by { -_1.cents }) do |row|
          (row[:parent_id] || row[:category_id]) == id
        end
      end
      lines.sort_by { -_1.cents }
    end

    # Spending by nature: fixed, essential, discretionary, and "unset" for rows without one.
    # The name is the nature's code; the page translates it.
    def natures
      spending_rows.group_by { _1[:nature] || "unset" }.map do |nature, rows|
        line(nature, nature, rows) { (_1[:nature] || "unset") == nature }
      end.sort_by { -_1.cents }
    end

    def payees(limit: 10)
      spending_rows.group_by { Insights.payee_key(_1) }.map do |key, rows|
        line(key, Insights.payee_label(rows.first), rows) { Insights.payee_key(_1) == key && Insights.spending?(_1) }
      end.sort_by { -_1.cents }.first(limit)
    end

    # Card installments paid this month, and the month each one ends.
    def installments
      spending_rows.select { _1[:installment_total] }.map do |row|
        left = row[:installment_total] - row[:installment_number]
        {row:, cents: -row[:amount_cents], left:, ends: left.zero? ? month : Insights.next_months(month, left).last}
      end.sort_by { -_1[:cents] }
    end

    def installments_cents = installments.sum { _1[:cents] }

    private

    def line(id, name, rows, children = [], &same)
      cents = Insights.spent_cents(rows)
      averages = @baseline.values.map { |month_rows| Insights.spent_cents(month_rows.select(&same)) }
      Line.new(id:, name:, cents:, average_cents: Insights.average(averages), share: Insights.share(cents, spending_cents),
        rows: rows.size, children:)
    end
  end
end
