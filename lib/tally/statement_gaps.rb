# frozen_string_literal: true

module Tally
  # Statements missing between the ones imported (issue #73). Without one month's conta
  # file the account's balance is off and nothing else says why.
  #
  # - A checking account's statements cover the periods in their file names, so a day
  #   between two imported periods that none of them covers is a missing file.
  # - A card has one bill a month, so a month between two imported due dates with no bill
  #   due in it is a missing bill.
  #
  # Only gaps between imports count: what comes before the first import or after the last
  # one isn't missing, just not imported yet.
  module StatementGaps
    # kind: "statement" (from and to are the first and last day nothing covers) or "bill"
    # (from and to are the first days of the first and last month with no bill due).
    Gap = Data.define(:kind, :from, :to) do
      # Whether the gap is whole calendar months, so it can be named by month.
      def whole_months? = kind == "bill" || (from.day == 1 && to.next_day.day == 1)
    end

    module_function

    # @param periods [Array<Range<Date>>] the periods imported statements cover
    # @return [Array<Gap>] the days none of them covers, oldest first
    def statements(periods)
      merged = periods.sort_by(&:begin).each_with_object([]) do |period, ranges|
        last = ranges.last
        if last && period.begin <= last.end.next_day
          ranges[-1] = last.begin..[last.end, period.end].max
        else
          ranges << period
        end
      end

      merged.each_cons(2).map { |before, after| Gap.new(kind: "statement", from: before.end.next_day, to: after.begin.prev_day) }
    end

    # @param due_dates [Array<Date>] the imported bills' due dates
    # @return [Array<Gap>] the months with no bill due between two that have one, oldest first
    def bills(due_dates)
      months = due_dates.map { Date.new(_1.year, _1.month, 1) }.uniq.sort
      months.each_cons(2).filter_map do |before, after|
        Gap.new(kind: "bill", from: before >> 1, to: after << 1) if after > before >> 1
      end
    end
  end
end
