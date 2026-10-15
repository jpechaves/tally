# frozen_string_literal: true

module Tally
  # Shared pieces of the monthly report, the cut suggestions and the installment calendar
  # (docs/architecture.md, section 8). Everything works on plain row hashes from
  # InsightRepo#rows, with integer cents, so every number traces back to its rows.
  module Insights
    # Kinds that are spending. A refund is spending with the other sign: it lowers the
    # category it belongs to. Transfers are neither spending nor income.
    SPENDING_KINDS = %w[purchase fee bill_payment refund].freeze
    INCOME_KINDS = %w[income].freeze

    UNCATEGORIZED = "Sem categoria"

    module_function

    def spending?(row) = SPENDING_KINDS.include?(row[:kind])

    def income?(row) = INCOME_KINDS.include?(row[:kind])

    # Spending as a positive number: a R$ 50 purchase is 5000, a refund of R$ 10 is -1000.
    def spent_cents(rows) = -rows.select { spending?(_1) }.sum { _1[:amount_cents] }

    def income_cents(rows) = rows.select { income?(_1) }.sum { _1[:amount_cents] }

    def month_of(row) = row[:occurred_on][0, 7]

    # "2026-09" -> "2026-06", "2026-07", "2026-08"
    def previous_months(month, count)
      date = Date.new(month[0, 4].to_i, month[5, 2].to_i, 1)
      (1..count).map { (date << _1).strftime("%Y-%m") }.reverse
    end

    def next_months(month, count)
      date = Date.new(month[0, 4].to_i, month[5, 2].to_i, 1)
      (1..count).map { (date >> _1).strftime("%Y-%m") }
    end

    def months_between(from, to)
      a = Date.new(from[0, 4].to_i, from[5, 2].to_i, 1)
      b = Date.new(to[0, 4].to_i, to[5, 2].to_i, 1)
      (b.year - a.year) * 12 + (b.month - a.month)
    end

    # The month a page opens on: the latest month with rows that is already over, since
    # the current one is usually only partly imported; the latest month if none is.
    def default_month(months, today: Date.today)
      current = today.strftime("%Y-%m")
      months.select { _1 < current }.max || months.max
    end

    # The average of whole cents, rounded half away from zero.
    def average(values) = values.empty? ? 0 : (values.sum.to_r / values.size).round

    # Who was paid, for grouping: the counterparty, or the words of the description.
    def payee_key(row) = Review.key(row)

    def payee_label(row) = row[:counterparty_name] || row[:description]

    # Integer percentage of part in whole, for display.
    def share(part, whole) = whole.zero? ? 0 : (part * 100.0 / whole).round(1)
  end
end
