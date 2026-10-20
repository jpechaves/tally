# frozen_string_literal: true

module Tally
  module Actions
    module Transactions
      # A category of your own for the rows picked in the transactions table: one row from
      # its category cell, the ticked rows at once, or (all) every row the filters find, on
      # every page, transfers aside since they have no category. Like picking it on a row's
      # page, it is manual (imports and rules leave it alone) and makes no rule. Back to the
      # same filters and page, saying how many rows changed.
      class Recategorize < Tally::Action
        include Deps["operations.assign_category", "repos.transaction_repo"]

        def handle(request, response)
          params = request.params
          filter = Tally::TransactionFilter.parse(params)
          ids, skipped = chosen(params, filter)
          halt 422, t("errors.could_not_save", reason: :no_filter) unless ids

          result = assign_category.call(ids:, category_id: params[:category_id].to_i)
          halt 422, t("errors.could_not_save", reason: result.failure) if result.failure?

          response.redirect_to "#{filter.pages.call(Tally::Pagination.param(params[:page]))}&changed=#{result.value!}&skipped=#{skipped}"
        end

        private

        # The ids to change and how many transfers were left out; nil for all rows when no
        # filter narrows them, so one click can't change the whole database.
        def chosen(params, filter)
          unless params[:all].to_s == "1"
            return [Array(params[:ids]).map(&:to_s).grep(Tally::TransactionFilter::ID).map(&:to_i), 0]
          end
          return unless filter.any?

          transfers, rows = transaction_repo.matching(filter).partition { _1[:kind] == "transfer" }
          [rows.map { _1[:id] }, transfers.size]
        end
      end
    end
  end
end
