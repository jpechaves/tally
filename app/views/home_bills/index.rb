# frozen_string_literal: true

module Tally
  module Views
    module HomeBills
      # Every home bill and how each month of the chosen span stands (Tally::HomeBills).
      class Index < Tally::View
        include Deps["repos.home_bill_repo", "repos.category_repo", "repos.transaction_repo"]

        expose :prefill, :span, decorate: false

        expose :months, decorate: false do |span|
          Tally::HomeBills.months(Date.today, span, first: transaction_repo.months.last)
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
