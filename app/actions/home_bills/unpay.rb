# frozen_string_literal: true

module Tally
  module Actions
    module HomeBills
      class Unpay < Tally::Action
        include Deps["repos.home_bill_repo"]

        def handle(request, response)
          bill = found(home_bill_repo, request)
          home_bill_repo.unpay(bill[:id], request.params[:month].to_s)
          response.redirect_to Tally::HomeBills.path(bill[:id], Tally::HomeBills.span(request.params[:months]))
        end
      end
    end
  end
end
