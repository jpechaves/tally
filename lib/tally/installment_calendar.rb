# frozen_string_literal: true

module Tally
  # Card installments already committed to future months (docs/architecture.md, 8.2): for
  # each purchase, its latest imported installment says how many are left, and each one
  # lands in a following month. Shows the money that frees up as purchases end.
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
      latest = rows.select { _1[:installment_total] && _1[:purchase_key] }
        .group_by { [_1[:account_id], _1[:purchase_key]] }
        .map { |_, installments| installments.max_by { [_1[:installment_number], _1[:occurred_on]] } }

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
  end
end
