# frozen_string_literal: true

module Tally
  module Relations
    class Transactions < Tally::DB::Relation
      schema :transactions, infer: true
    end
  end
end
