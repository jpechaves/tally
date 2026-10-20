# frozen_string_literal: true

module Tally
  module Views
    module Transactions
      class Show < Tally::View
        include Deps["repos.category_repo", "repos.transaction_repo", "repos.trip_repo"]

        expose :row

        # The page that linked here, for the way back (issue #87).
        expose :back, decorate: false

        # The error the adjustment form sent back, if any (config/i18n, "errors").
        expose :error_code, decorate: false

        expose :categories do
          category_repo.tree
        end

        # Trips the row can be added to or taken out of (Tally::Trip).
        expose :trips, decorate: false do
          trip_repo.all
        end

        # Rows that could have paid this purchase back, for the reimbursed form.
        expose :refund_candidates do |row|
          next [] if row[:kind] == "transfer" || !row[:amount_cents].negative? || row[:refunds_transaction_id]

          transaction_repo.refund_candidates(row)
        end
      end
    end
  end
end
