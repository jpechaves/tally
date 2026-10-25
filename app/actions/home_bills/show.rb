# frozen_string_literal: true

module Tally
  module Actions
    module HomeBills
      class Show < Tally::Action
        include Deps["repos.home_bill_repo"]

        def handle(request, response)
          response[:home_bill] = found(home_bill_repo, request)
          response[:span] = Tally::HomeBills.span(request.params[:months])
        end
      end
    end
  end
end
