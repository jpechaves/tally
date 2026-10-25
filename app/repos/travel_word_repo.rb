# frozen_string_literal: true

module Tally
  module Repos
    # The travel list that trip suggestions look for (Tally::Trip#suggestions).
    class TravelWordRepo < Tally::DB::Repo
      def all = travel_words.dataset.order { lower(word) }.all

      def words = all.map { _1[:word] }

      # Ignores a word already there, in any case or accents.
      def add(word)
        folded = Tally::Search.fold(word)
        return if words.any? { Tally::Search.fold(_1) == folded }

        travel_words.dataset.insert(word:)
      end

      def delete(id) = travel_words.dataset.where(id:).delete
    end
  end
end
