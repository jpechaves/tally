# frozen_string_literal: true

module Tally
  module Views
    module HomeBills
      # Every home bill and how each month of the chosen span stands (Tally::HomeBills).
      class Index < Tally::View
        include Tally::Views::HomeBillChart
        include Deps["repos.home_bill_repo", "repos.category_repo", "repos.transaction_repo", "repos.insight_repo"]

        expose :prefill, :span, decorate: false

        expose :months, decorate: false do |span|
          Tally::HomeBills.months(Date.today, span, first: transaction_repo.months.last)
        end

        # A month a row surely paid counts as paid (Tally::HomeBills.with_found).
        expose :bills, decorate: false do |months|
          bills = home_bill_repo.all.map { _1.merge(payee_key: home_bill_repo.payee_key(_1)) }
          payments = home_bill_repo.payments(bills.map { _1[:id] }, months)
          linked = home_bill_repo.linked(payments.values).values
          rows = insight_repo.rows(from: Tally::Insights.previous_months(months.first, 1).first, to: Tally::Insights.next_months(months.last, 1).first)
            .reject { linked.include?(_1[:id]) }
          bills.map { |bill| [bill, Tally::HomeBills.status_by_month(bill, months, Tally::HomeBills.with_found(bill, months, rows, payments), today: Date.today)] }
        end

        # Paid toward all the bills each month, against what they are expected to cost.
        expose :chart, decorate: false do
          home_bill_chart(home_bill_repo.all.map { _1.merge(payee_key: home_bill_repo.payee_key(_1)) })
        end

        expose :categories do
          category_repo.tree
        end
      end
    end
  end
end
