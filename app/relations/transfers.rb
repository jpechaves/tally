# frozen_string_literal: true

module Tally
  module Relations
    class Transfers < Tally::DB::Relation
      schema :transfers, infer: true
    end
  end
end
