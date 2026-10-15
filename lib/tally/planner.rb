# frozen_string_literal: true

module Tally
  # "I want to save R$ X a month" (docs/architecture.md, section 8.4).
  #
  # The baseline is what you do today: average monthly income and spending per category
  # over the last complete months. The gap between the target and what you already save
  # is split across categories in proportion to how much each may be cut (its nature's
  # maximum cut), with Money#allocate, so the cuts add up to the gap exactly. When the
  # cuts can't cover the gap, everything cuttable is cut and the rest is a shortfall, with
  # the other levers listed: fixed costs to renegotiate and installments ending soon.
  class Planner
    Line = Data.define(:category_id, :name, :parent_name, :nature, :max_cut_pct, :baseline_cents, :max_cut_cents,
      :cut_cents) do
      def proposed_cents = baseline_cents - cut_cents
    end

    attr_reader :target_cents, :months

    # @param rows [Array<Hash>] rows of the baseline months (InsightRepo#rows)
    # @param months [Array<String>] the baseline months, "YYYY-MM"
    # @param target_cents [Integer] how much to save each month
    def initialize(rows, months:, target_cents:)
      raise ArgumentError, "the target must be positive" unless target_cents.positive?

      @months = months
      @target_cents = target_cents
      @rows = rows.select { months.include?(Insights.month_of(_1)) }
    end

    def income_cents = average(Insights.income_cents(@rows))

    def spending_cents = average(Insights.spent_cents(@rows))

    def saved_today_cents = income_cents - spending_cents

    def gap_cents = target_cents - saved_today_cents

    def already_there? = !gap_cents.positive?

    def cuttable_cents = lines.sum(&:max_cut_cents)

    def shortfall_cents = already_there? ? 0 : [gap_cents - cuttable_cents, 0].max

    def cuts_cents = lines.sum(&:cut_cents)

    # One line per category with spending, biggest first. Rows with no category count in
    # the spending but can't get a budget; see #uncategorized_cents.
    def lines
      @lines ||= begin
        base = @rows.select { Insights.spending?(_1) && _1[:category_id] }.group_by { _1[:category_id] }.map do |id, rows|
          first = rows.first
          baseline = average(Insights.spent_cents(rows))
          max_cut = [baseline, 0].max * first[:max_cut_pct].to_i / 100
          {category_id: id, name: first[:category_name], parent_name: first[:parent_name], nature: first[:nature],
           max_cut_pct: first[:max_cut_pct].to_i, baseline_cents: baseline, max_cut_cents: max_cut}
        end.select { _1[:baseline_cents].positive? }

        cuts = cuts_for(base)
        base.zip(cuts).map { |line, cut| Line.new(**line, cut_cents: cut) }.sort_by { [-_1.baseline_cents, _1.name] }
      end
    end

    def uncategorized_cents
      average(Insights.spent_cents(@rows.select { Insights.spending?(_1) && _1[:category_id].nil? }))
    end

    # Fixed categories, biggest first: they can't be trimmed month to month, but a
    # contract can be renegotiated.
    def fixed_lines = lines.select { _1.nature == "fixed" }

    private

    def average(cents) = (cents.to_r / @months.size).round

    def cuts_for(base)
      return base.map { 0 } if already_there? || base.empty?

      weights = base.map { _1[:max_cut_cents] }
      return base.map { 0 } if weights.sum.zero?
      return weights if gap_cents >= weights.sum

      Money.new(gap_cents).allocate(weights).map(&:cents)
    end
  end
end
