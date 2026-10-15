# frozen_string_literal: true

module Tally
  module Relations
    class Budgets < Tally::DB::Relation
      schema :budgets, infer: true
    end
  end
end
