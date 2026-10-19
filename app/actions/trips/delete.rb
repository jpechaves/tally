# frozen_string_literal: true

module Tally
  module Actions
    module Trips
      # Deletes a trip and your choices of rows; the rows themselves stay.
      class Delete < Tally::Action
        include Deps["repos.trip_repo"]

        def handle(request, response)
          halt 404 if trip_repo.delete(request.params[:id].to_i).zero?

          response.redirect_to "/trips"
        end
      end
    end
  end
end
