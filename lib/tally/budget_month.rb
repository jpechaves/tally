# frozen_string_literal: true

module Tally
  # One month against its budgets and the savings target (docs/architecture.md, 8.5): spent
  # and limit per category with its pace, what was saved so far, a projection to the end
  # of the month, and, once the month is over, its score.
  class BudgetMonth
    AHEAD_OF_PACE_PCT = 10

    Line = Data.define(:category_id, :name, :parent_name, :limit_cents, :spent_cents, :expected_cents) do
      def left_cents = limit_cents - spent_cents

      def over? = spent_cents > limit_cents

      # Spent so far against what the pace allows by today: 100 is on pace.
      def pace_pct = expected_cents.zero? ? (spent_cents.positive? ? nil : 0) : (spent_cents * 100.0 / expected_cents).round

      def ahead_of_pace? = spent_cents * 100 > expected_cents * (100 + AHEAD_OF_PACE_PCT)
    end

    attr_reader :month, :target_cents

    # @param rows [Array<Hash>] the month's rows (InsightRepo#rows)
    # @param budgets [Hash{Integer => Integer}] category id => monthly limit in cents
    # @param categories [Hash{Integer => Hash}] category id => {name:, parent_name:}
    # @param target_cents [Integer, nil] the active plan's target
    # @param expected_income_cents [Integer] the income expected in a month
    # @param expected_unbudgeted_cents [Integer] the spending expected outside the budgets in a month
    # @param today [Date]
    def initialize(rows, month:, budgets:, categories:, today:, target_cents: nil, expected_income_cents: 0,
      expected_unbudgeted_cents: 0)
      @month = month
      @rows = rows.select { Insights.month_of(_1) == month }
      @budgets = budgets
      @categories = categories
      @target_cents = target_cents
      @expected_income_cents = expected_income_cents
      @expected_unbudgeted_cents = expected_unbudgeted_cents
      @first = Date.new(month[0, 4].to_i, month[5, 2].to_i, 1)
      @days = (@first >> 1) - @first
      @elapsed_days = if today < @first then 0
      elsif today >= @first >> 1 then @days
      else today.day
      end
    end

    def complete? = @elapsed_days == @days

    # Share of the month gone, 0..1.
    def elapsed = Rational(@elapsed_days, @days)

    def income_cents = Insights.income_cents(@rows)

    def spending_cents = Insights.spent_cents(@rows)

    def saved_cents = income_cents - spending_cents

    def lines
      @lines ||= @budgets.map do |category_id, limit|
        rows = @rows.select { _1[:category_id] == category_id && Insights.spending?(_1) }
        category = @categories.fetch(category_id, {})
        Line.new(category_id:, name: category.fetch(:name, "##{category_id}"), parent_name: category[:parent_name],
          limit_cents: limit, spent_cents: Insights.spent_cents(rows), expected_cents: (limit * elapsed).round)
      end.sort_by { [-_1.limit_cents, _1.name] }
    end

    # Spending in categories with no budget (and rows with no category).
    def unbudgeted_cents = spending_cents - lines.sum(&:spent_cents)

    # Income so far plus what's still expected, minus spending so far, what's left in each
    # budget, and what's still expected outside the budgets: spending there is treated like
    # one more budget whose limit is its usual amount.
    def projected_saved_cents
      income = [income_cents, @expected_income_cents].max
      income - spending_cents - lines.sum { [_1.left_cents, 0].max } - unbudgeted_left_cents
    end

    def unbudgeted_left_cents = complete? ? 0 : [@expected_unbudgeted_cents - unbudgeted_cents, 0].max

    def on_track? = target_cents.nil? || projected_saved_cents >= target_cents

    def over_lines = lines.select(&:over?)

    # The month-end score, once the month is over: the target against what was actually
    # saved, and which categories went over their limit.
    def score
      return unless complete? && target_cents

      {target_cents:, saved_cents:, hit: saved_cents >= target_cents, difference_cents: saved_cents - target_cents,
       over: over_lines}
    end
  end
end
