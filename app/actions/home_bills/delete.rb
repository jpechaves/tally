# frozen_string_literal: true

module Tally
  module Actions
    module HomeBills
      # Deletes a bill, its payments and receipts, and the receipt files nothing else uses.
      class Delete < Tally::Action
        include Deps["repos.home_bill_repo"]

        def handle(request, response)
          bill = found(home_bill_repo, request)
          home_bill_repo.delete(bill[:id]).each { Tally::Receipts.delete(Tally::Receipts.dir, _1) }
          response.redirect_to "/home-bills"
        end
      end
    end
  end
end
