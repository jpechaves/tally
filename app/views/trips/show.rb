# frozen_string_literal: true

module Tally
  module Views
    module Trips
      class Show < Tally::View
        include Deps["repos.account_repo", "repos.transaction_repo", "repos.trip_repo"]
        include Tally::Views::TripCosts

        expose :trip, decorate: false

        expose :result, decorate: false do |trip|
          build_trip(trip)
        end

        expose :places, decorate: false do |result|
          Tally::Places.default.of(result.rows)
        end

        # Rows its dates would bring in that you took out, so they can go back.
        expose :taken_out, decorate: false do |trip|
          ids = trip[:choices].reject { |_, included| included }.keys
          ids.empty? ? [] : transaction_repo.rows(ids)
        end

        expose :account_names, decorate: false do |trip|
          names = account_repo.all.to_h { [_1.id, _1.name] }
          trip[:account_ids].map { names[_1] }
        end
      end
    end
  end
end
