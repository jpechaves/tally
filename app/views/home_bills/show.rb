# frozen_string_literal: true

module Tally
  module Views
    module HomeBills
      # One bill: each month with its payment, the rows that could be it, and its receipts.
      class Show < Tally::View
        include Deps["repos.home_bill_repo", "repos.insight_repo"]

        # With its payee as the rows name it today.
        expose :bill, decorate: false do |home_bill:|
          home_bill.merge(payee_key: home_bill_repo.payee_key(home_bill))
        end

        # This month first.
        expose :months, decorate: false do |bill|
          months = Tally::HomeBills.months(Date.today)
          Tally::HomeBills.status_by_month(bill, months, home_bill_repo.payments([bill[:id]], months), today: Date.today).reverse
        end

        # [account name, external id] => the row's id today.
        expose :linked, decorate: false do |months|
          home_bill_repo.linked(months.filter_map(&:payment))
        end

        expose :rows, decorate: false do |months, linked|
          from, to = months.map(&:month).minmax
          ids = linked.values
          insight_repo.rows(from: Tally::Insights.previous_months(from, 1).first, to: Tally::Insights.next_months(to, 1).first)
            .reject { ids.include?(_1[:id]) }
        end

        expose :receipts, decorate: false do |bill|
          home_bill_repo.receipts([bill[:id]])
        end
      end
    end
  end
end
