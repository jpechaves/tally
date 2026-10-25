# frozen_string_literal: true

module Tally
  module Actions
    module Trips
      # Changes a trip's name, dates and accounts; the rows you added or took out stay chosen.
      class Update < Tally::Action
        include Deps["repos.account_repo", "repos.trip_repo"]
        include Form

        def handle(request, response)
          trip = found(trip_repo, request)
          trip_repo.update(trip[:id], **trip_params(request))
          response.redirect_to "/trips/#{trip[:id]}"
        end
      end
    end
  end
end
