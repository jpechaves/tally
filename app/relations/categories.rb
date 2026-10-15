# frozen_string_literal: true

module Tally
  module Relations
    class Categories < Tally::DB::Relation
      schema :categories, infer: true
    end
  end
end
