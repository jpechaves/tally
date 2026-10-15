# frozen_string_literal: true

module Tally
  module Relations
    class Counterparties < Tally::DB::Relation
      schema :counterparties, infer: true
    end
  end
end
