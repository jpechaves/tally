# frozen_string_literal: true

module Tally
  module Views
    module HomeBills
      # Every home bill and how the month before and this month stand (Tally::HomeBills).
      class Index < Tally::View
        include Deps["repos.home_bill_repo", "repos.category_repo"]

        expose :prefill, decorate: false

        expose :months, decorate: false do
          Tally::HomeBills.months(Date.today)
        end

        expose :bills, decorate: false do |months|
          bills = home_bill_repo.all
          payments = home_bill_repo.payments(bills.map { _1[:id] }, months)
          bills.map { |bill| [bill, Tally::HomeBills.status_by_month(bill, months, payments, today: Date.today)] }
        end

        expose :categories do
          category_repo.tree
        end
      end
    end
  end
end
