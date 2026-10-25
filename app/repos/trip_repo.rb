# frozen_string_literal: true

module Tally
  module Repos
    # Trips, their accounts and your choices of rows (Tally::Trip).
    class TripRepo < Tally::DB::Repo
      include Deps["repos.insight_repo", "repos.travel_word_repo"]

      # Newest first, as Tally::Trip wants them: account_ids and choices included.
      def all = trips.dataset.order(Sequel.desc(:starts_on), Sequel.desc(:id)).all.map { with_choices(_1) }

      def find(id)
        trip = trips.dataset.where(id:).first
        with_choices(trip) if trip
      end

      # @param account_ids [Array<Integer>] empty for all accounts
      def create(name:, starts_on:, ends_on:, account_ids:)
        trips.transaction do
          id = trips.dataset.insert(name:, starts_on:, ends_on:)
          trip_accounts.dataset.import(%i[trip_id account_id], account_ids.map { [id, _1] })
          id
        end
      end

      # New name, dates and accounts; your choices of rows (trip_rows) stay.
      def update(id, name:, starts_on:, ends_on:, account_ids:)
        trips.transaction do
          trips.dataset.where(id:).update(name:, starts_on:, ends_on:)
          trip_accounts.dataset.where(trip_id: id).delete
          trip_accounts.dataset.import(%i[trip_id account_id], account_ids.map { [id, _1] })
        end
      end

      def delete(id) = trips.dataset.where(id:).delete

      def any? = !trips.dataset.empty?

      # included: true adds the row, false takes it out, nil goes back to its dates deciding.
      def choose(trip_id, transaction_id, included)
        rows = trip_rows.dataset.where(trip_id:, transaction_id:)
        return rows.delete if included.nil?

        trip_rows.dataset.insert_conflict(target: %i[trip_id transaction_id], update: {included: Sequel[:excluded][:included]})
          .insert(trip_id:, transaction_id:, included: included ? 1 : 0)
      end

      # From Trip::DAYS_BEFORE days before it, for its suggestions.
      # @param costs [Hash] account id => TopUps::Cost
      def build(trip, costs: {})
        added = trip[:choices].select { |_, included| included }.keys
        from = (Date.iso8601(trip[:starts_on]) - Tally::Trip::DAYS_BEFORE).iso8601
        Tally::Trip.new(trip, insight_repo.trip_rows(starts_on: from, ends_on: trip[:ends_on], ids: added),
          installments: insight_repo.installment_rows, costs:, words: travel_word_repo.words)
      end

      # Ids of the rows of every trip, for the report's "hide trips".
      def row_ids = all.flat_map { build(_1).ids }.uniq

      private

      def with_choices(trip)
        trip.merge(
          account_ids: trip_accounts.dataset.where(trip_id: trip[:id]).select_map(:account_id),
          choices: trip_rows.dataset.where(trip_id: trip[:id]).to_h { [_1[:transaction_id], _1[:included] == 1] }
        )
      end
    end
  end
end
