# auto_register: false
# frozen_string_literal: true

module Tally
  module Views
    # Paid toward the bills each month (Tally::HomeBills.chart), against what they are
    # expected to cost, over the last twelve months: one bill's page or all of them.
    module HomeBillChart
      def home_bill_chart(bills)
        months = Tally::HomeBills.chart_months(Date.today, first: transaction_repo.months.last)
        payments = home_bill_repo.payments(bills.map { _1[:id] }, months)
        rows = insight_repo.rows(from: months.first, to: months.last, without: home_bill_repo.linked(payments.values).values)
        {months:, **Tally::HomeBills.chart(bills, months, rows, payments), expected: bills.sum { _1[:expected_cents].to_i }}
      end
    end
  end
end
