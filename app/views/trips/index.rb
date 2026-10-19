# frozen_string_literal: true

module Tally
  module Views
    module Trips
      class Index < Tally::View
        include Deps["repos.account_repo", "repos.transaction_repo", "repos.trip_repo"]
        include Tally::Views::TripCosts

        expose :accounts do
          account_repo.all
        end

        # Each trip with what it adds up to.
        expose :trips, decorate: false do
          trip_repo.all.map { [_1, build_trip(_1)] }
        end
      end
    end
  end
end
