# frozen_string_literal: true

module Tally
  module Actions
    module Trips
      # A new trip: a name, its first and last day, and the accounts to look in (none for all).
      class Create < Tally::Action
        include Deps["repos.account_repo", "repos.trip_repo"]

        DATE = /\A\d{4}-\d{2}-\d{2}\z/

        def handle(request, response)
          name = request.params[:name].to_s.strip[0, 200]
          starts_on, ends_on = [request.params[:starts_on], request.params[:ends_on]].map { date(_1) }
          halt 422, t("errors.invalid_trip") if name.empty? || !starts_on || !ends_on || starts_on > ends_on

          known = account_repo.all.map(&:id)
          account_ids = Array(request.params[:account_ids]).map(&:to_i) & known
          id = trip_repo.create(name:, starts_on:, ends_on:, account_ids:)
          response.redirect_to "/trips/#{id}"
        end

        private

        def date(value) = begin
          Date.iso8601(value.to_s[DATE].to_s).iso8601
        rescue
          nil
        end
      end
    end
  end
end
