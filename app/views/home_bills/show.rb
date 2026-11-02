# frozen_string_literal: true

module Tally
  module Views
    module HomeBills
      # One bill: each month with its payment, the rows that could be it, and its receipts.
      class Show < Tally::View
        include Deps["repos.home_bill_repo", "repos.insight_repo", "repos.person_repo", "repos.transaction_repo"]

        expose :span, decorate: false

        # With its payee as the rows name it today.
        expose :bill, decorate: false do |home_bill:|
          home_bill.merge(payee_key: home_bill_repo.payee_key(home_bill))
        end

        private_expose :shown, decorate: false do |span|
          Tally::HomeBills.months(Date.today, span, first: transaction_repo.months.last)
        end

        # This month first, a month a row surely paid counted as paid (Tally::HomeBills.with_found).
        expose :months, decorate: false do |bill, shown, rows|
          payments = Tally::HomeBills.with_found(bill, shown, rows, home_bill_repo.payments([bill[:id]], shown))
          Tally::HomeBills.status_by_month(bill, shown, payments, today: Date.today).reverse
        end

        # [account name, external id] => the row's id today.
        expose :linked, decorate: false do |months|
          home_bill_repo.linked(months.filter_map(&:payment))
        end

        # Rows from a month either side, minus those a payment of any nearby month already uses.
        expose :rows, decorate: false do |bill, shown|
          from, to = shown.minmax
          around = Tally::Insights.previous_months(from, 2) + [from, to].uniq + Tally::Insights.next_months(to, 2)
          ids = home_bill_repo.linked(home_bill_repo.payments([bill[:id]], around).values).values
          insight_repo.rows(from: around[1], to: around[-2]).reject { ids.include?(_1[:id]) }
        end

        # Paid toward the bill each month, against what it is expected to cost.
        expose :chart, decorate: false do |bill|
          months = Tally::HomeBills.chart_months(Date.today, first: transaction_repo.months.last)
          rows = insight_repo.rows(from: months.first, to: months.last)
          paid = Tally::HomeBills.paid_by_month(bill, months, rows, home_bill_repo.payments([bill[:id]], months))
          {months:, paid:, expected: bill[:expected_cents].to_i}
        end

        # Who could have paid by hand; with only you, nobody to pick.
        expose :people, decorate: false do
          person_repo.all
        end

        expose :receipts, decorate: false do |bill|
          home_bill_repo.receipts([bill[:id]])
        end
      end
    end
  end
end
