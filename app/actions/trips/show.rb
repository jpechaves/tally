# frozen_string_literal: true

module Tally
  module Actions
    module Trips
      class Show < Tally::Action
        include Deps["repos.trip_repo"]

        def handle(request, response)
          response[:trip] = found(trip_repo, request)
        end
      end
    end
  end
end
