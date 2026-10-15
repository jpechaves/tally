# frozen_string_literal: true

module Tally
  module Relations
    class Imports < Tally::DB::Relation
      schema :imports, infer: true
    end
  end
end
