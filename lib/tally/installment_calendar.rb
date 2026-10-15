# frozen_string_literal: true

module Tally
  # Card installments already committed to future months (docs/architecture.md, 8.2): for
  # each purchase, its latest imported installment says how many are left, and each one
  # lands in a following month. Shows the money that frees up as purchases end.
  # Installments of one purchase are linked by #purchase_of.
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
        # Each row of the latest installment is one purchase: two identical purchases
        # made the same month both stay.
        newest = installments.map { _1[:installment_number] }.max
        installments.select { _1[:installment_number] == newest }
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

    # Which purchase an installment belongs to: card, merchant, count, and the month of
    # its first installment (installment 3 of a bill in October started in August). The
    # bank's purchase key can't link them: the first installment carries the rounding
    # cents, so its amount (part of the key) differs from the others.
    def purchase_of(row)
      month = Insights.month_of(row)
      first = row[:installment_number] > 1 ? Insights.previous_months(month, row[:installment_number] - 1).first : month
      [row[:account_id], Categories.fold(row[:description]), row[:installment_total], first]
    end
  end
end
