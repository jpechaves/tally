# frozen_string_literal: true

module Tally
  module Actions
    module Trips
      class Show < Tally::Action
        include Deps["repos.trip_repo"]

        def handle(request, response)
          trip = trip_repo.find(request.params[:id].to_i)
          halt 404 unless trip

          response[:trip] = trip
        end
      end
    end
  end
end
