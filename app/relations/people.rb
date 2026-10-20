# frozen_string_literal: true

module Tally
  module Relations
    class People < Tally::DB::Relation
      schema :people, infer: true
    end
  end
end
