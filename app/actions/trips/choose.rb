# frozen_string_literal: true

module Tally
  module Actions
    module Trips
      # Adds a row to a trip (included=1), takes it out (0), or lets its dates decide again
      # (blank). For an installment, the choice covers its whole card purchase.
      class Choose < Tally::Action
        include Deps["repos.trip_repo", "repos.transaction_repo"]

        CHOICES = {"1" => true, "0" => false}.freeze

        def handle(request, response)
          trip = trip_repo.find(request.params[:trip_id].to_i)
          row = transaction_repo.row(request.params[:transaction_id].to_i)
          halt 404 unless trip && row

          trip_repo.choose(trip[:id], row[:id], CHOICES[request.params[:included].to_s])
          response.redirect_to back_param(request.params[:back]) || "/trips/#{trip[:id]}"
        end
      end
    end
  end
end
