# frozen_string_literal: true

module Tally
  module Relations
    class TripRows < Tally::DB::Relation
      schema :trip_rows, infer: true
    end
  end
end
