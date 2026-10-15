# frozen_string_literal: true

module Tally
  # Card installments already committed to future months (docs/architecture.md, 8.2): for
  # each purchase, its latest imported installment says how many are left, and each one
  # lands in a following month. Shows the money that frees up as purchases end.
  # Installments of one purchase are linked by #purchase_of and #series.
  class InstallmentCalendar
    Purchase = Data.define(:key, :description, :account_name, :cents, :number, :total, :last_month, :ends) do
      def left = total - number

      # Installments still to pay in `month` or later.
      def left_from(month) = Insights.next_months(last_month, left).count { _1 >= month }
    end

    attr_reader :from

    # @param rows [Array<Hash>] installment rows (installment_total set), any month
    # @param from [String] "YYYY-MM": the first month to count. Earlier months are past,
    #   even when their bills aren't imported yet.
    def initialize(rows, from:)
      @from = from
      latest = rows.select { _1[:installment_total] }.group_by { purchase_of(_1) }.flat_map do |_, installments|
        series(installments).map(&:last)
      end

      @purchases = latest.filter_map do |row|
        left = row[:installment_total] - row[:installment_number]
        month = Insights.month_of(row)
        next unless left.positive? && Insights.next_months(month, left).last >= from

        Purchase.new(key: row[:purchase_key], description: row[:description], account_name: row[:account_name],
          cents: -row[:amount_cents], number: row[:installment_number], total: row[:installment_total],
          last_month: month, ends: Insights.next_months(month, left).last)
      end.sort_by { [_1.ends, _1.description] }
    end

    attr_reader :purchases

    # Month => cents committed, for each month that has any.
    def months
      @purchases.each_with_object(Hash.new(0)) do |purchase, totals|
        Insights.next_months(purchase.last_month, purchase.left).each do |month|
          totals[month] += purchase.cents if month >= @from
        end
      end.sort.to_h
    end

    def total_cents = months.values.sum

    private

    # Installments of the same card, merchant and count, before they are split into
    # purchases by #series. The bank's purchase key can't link them: the first installment
    # carries the rounding cents, so its amount (part of the key) differs from the others.
    def purchase_of(row)
      [row[:account_id], Categories.fold(row[:description]), row[:installment_total]]
    end

    # Splits one merchant's installments into purchases, in bill order. An installment
    # continues the purchase whose last installment is lower and on an earlier bill, one
    # step per bill or more. Paying in advance puts several installments on one bill, and bill
    # months, not posting dates, keep a purchase whose installments post on the 1st of one
    # month and the 2nd of the next together. Two identical purchases on one bill stay two.
    def series(installments)
      installments.sort_by { [bill_month(_1), _1[:installment_number]] }.each_with_object([]) do |row, all|
        month = bill_month(row)
        number = row[:installment_number]
        # Steps ahead of the bills (paid early) or level with them; never behind, which
        # would be a different purchase.
        open = all.select do |chain|
          step = number - chain.last[:installment_number]
          step.positive? && step >= months_apart(bill_month(chain.last), month)
        end
        on_time, early = open.partition { number - _1.last[:installment_number] == months_apart(bill_month(_1.last), month) }
        chain = on_time.max_by { _1.last[:installment_number] } || early.max_by { _1.last[:installment_number] }
        chain ? chain << row : all << [row]
      end
    end

    # The month of the bill the installment is on, or the month it posted when the bill
    # isn't known.
    def bill_month(row) = (row[:bill_due_on] || row[:occurred_on])[0, 7]

    def months_apart(from, to) = ((to[0, 4].to_i * 12) + to[5, 2].to_i) - ((from[0, 4].to_i * 12) + from[5, 2].to_i)
  end
end
