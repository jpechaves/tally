# frozen_string_literal: true

module Tally
  module Views
    module Transactions
      class Index < Tally::View
        include Deps["repos.account_repo", "repos.category_repo", "repos.person_repo", "repos.transaction_repo", "repos.trip_repo"]

        PER_PAGE = Tally::Pagination::PER_PAGE

        expose :filter, decorate: false
        expose :return_to, decorate: false
        expose :changed, :skipped, decorate: false

        expose :accounts do
          account_repo.all
        end

        expose :months do
          transaction_repo.months
        end

        expose :categories do
          category_repo.tree
        end

        # Rows and net of everything the filters match, not just this page.
        expose :totals, decorate: false do |filter|
          transaction_repo.totals(filter)
        end

        expose :pagination, decorate: false do |totals, page:|
          Tally::Pagination.page(page, total: totals[:rows], per_page: PER_PAGE)
        end

        # Where a change of category from the table comes back to: these filters and page,
        # and the page that sent you here.
        expose :back, decorate: false do |filter, pagination, return_to|
          filter.query.merge(page: pagination.number, back: return_to).compact
        end

        expose :rows do |filter, pagination|
          transaction_repo.list(filter, limit: pagination.limit, offset: pagination.offset)
        end

        # The card purchase the purchase filter shows, with what is left to pay of it.
        expose :purchase, decorate: false do |filter|
          next unless filter.purchase

          series = transaction_repo.installment_series(filter.purchase)
          Tally::InstallmentCalendar::Purchase.of(series) unless series.empty?
        end

        expose :this_month, decorate: false do
          Date.today.strftime("%Y-%m")
        end

        # The trip the trip filter shows.
        # Whose accounts the person filter shows (issue #21).
        expose :person_name, decorate: false do |filter|
          person_repo.find(filter.person)&.name if filter.person
        end

        expose :trip_name, decorate: false do |filter|
          trip_repo.find(filter.trip)&.fetch(:name) if filter.trip
        end

        # Who the payee filter shows, named like the report names it.
        expose :payee_name, decorate: false do |filter, rows|
          next unless filter.payee

          rows.empty? ? filter.payee.split(":", 2).last : Tally::Insights.payee_label(rows.first)
        end
      end
    end
  end
end
