# frozen_string_literal: true

module Tally
  module Views
    module Trips
      class Index < Tally::View
        include Deps["repos.account_repo", "repos.person_repo", "repos.transaction_repo", "repos.trip_repo"]
        include Tally::Views::TripCosts
        include Tally::Views::TripForm

        # Each trip with what it adds up to.
        expose :trips, decorate: false do
          trip_repo.all.map { [_1, build_trip(_1)] }
        end

        # Where every trip went.
        expose :places, decorate: false do |trips|
          Tally::Places.default.of(trips.flat_map { |_, result| result.rows })
        end
      end
    end
  end
end
