# frozen_string_literal: true

module Tally
  module Actions
    module Trips
      # A new trip: a name, its first and last day, and the accounts to look in.
      class Create < Tally::Action
        include Deps["repos.account_repo", "repos.trip_repo"]
        include Form

        def handle(request, response)
          response.redirect_to "/trips/#{trip_repo.create(**trip_params(request))}"
        end
      end
    end
  end
end
