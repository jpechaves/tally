# frozen_string_literal: true

module Tally
  module Relations
    class SavingsPlanLines < Tally::DB::Relation
      schema :savings_plan_lines, infer: true
    end
  end
end
