# frozen_string_literal: true

module Tally
  module Relations
    class Trips < Tally::DB::Relation
      schema :trips, infer: true
    end
  end
end
