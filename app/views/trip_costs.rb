# auto_register: false
# frozen_string_literal: true

module Tally
  module Views
    # What a trip's rows in another currency cost in reais: the average of their account's
    # top-ups up to the end of the trip's last month (Tally::TopUps), like the account report.
    module TripCosts
      def trip_costs(trip)
        through = "#{trip[:ends_on][0, 7]}-31"
        account_repo.all.reject { _1.currency == Tally::Money::DEFAULT_CURRENCY }
          .to_h { [_1.id, Tally::TopUps.average(transaction_repo.top_ups(_1.id, through:))] }.compact
      end

      def build_trip(trip) = trip_repo.build(trip, costs: trip_costs(trip))
    end
  end
end
