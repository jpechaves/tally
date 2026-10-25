# frozen_string_literal: true

module Tally
  module Views
    module HomeBills
      # Every home bill and how each month of the chosen span stands (Tally::HomeBills).
      class Index < Tally::View
        include Deps["repos.home_bill_repo", "repos.category_repo", "repos.transaction_repo", "repos.insight_repo"]

        expose :prefill, :span, decorate: false

        expose :months, decorate: false do |span|
          Tally::HomeBills.months(Date.today, span, first: transaction_repo.months.last)
        end

        expose :bills, decorate: false do |months|
          bills = home_bill_repo.all
          payments = home_bill_repo.payments(bills.map { _1[:id] }, months)
          bills.map { |bill| [bill, Tally::HomeBills.status_by_month(bill, months, payments, today: Date.today)] }
        end

        # Paid toward all the bills each month, against what they are expected to cost.
        expose :chart, decorate: false do
          bills = home_bill_repo.all.map { _1.merge(payee_key: home_bill_repo.payee_key(_1)) }
          months = Tally::HomeBills.chart_months(Date.today, first: transaction_repo.months.last)
          rows = insight_repo.rows(from: months.first, to: months.last)
          payments = home_bill_repo.payments(bills.map { _1[:id] }, months)
          paid = bills.map { Tally::HomeBills.paid_by_month(_1, months, rows, payments) }.transpose
          {months:, paid: paid.map { _1.compact.sum if _1.any? }, expected: bills.sum { _1[:expected_cents].to_i }}
        end

        expose :categories do
          category_repo.tree
        end
      end
    end
  end
end
