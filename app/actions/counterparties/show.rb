# frozen_string_literal: true

module Tally
  module Actions
    module Counterparties
      # The form for your own name and note for one counterparty.
      class Show < Tally::Action
        include Deps["repos.counterparty_repo"]

        def handle(request, response)
          response[:party] = found(counterparty_repo, request)
          response[:back] = back_param(request.params[:back])
        end
      end
    end
  end
end
