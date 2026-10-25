# frozen_string_literal: true

module Tally
  module Relations
    class TravelWords < Tally::DB::Relation
      schema :travel_words, infer: true
    end
  end
end
