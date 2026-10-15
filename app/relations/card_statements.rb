# frozen_string_literal: true

module Tally
  module Relations
    class CardStatements < Tally::DB::Relation
      schema :card_statements, infer: true
    end
  end
end
