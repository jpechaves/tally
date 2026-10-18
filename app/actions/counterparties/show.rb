# frozen_string_literal: true

module Tally
  module Actions
    module Counterparties
      # The form for your own name and note for one counterparty.
      class Show < Tally::Action
        include Deps["repos.counterparty_repo"]

        def handle(request, response)
          party = counterparty_repo.find(request.params[:id].to_i)
          halt 404 unless party

          response[:party] = party
          response[:back] = back_param(request.params[:back])
        end
      end
    end
  end
end
