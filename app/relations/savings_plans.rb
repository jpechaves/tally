# frozen_string_literal: true

module Tally
  module Relations
    class SavingsPlans < Tally::DB::Relation
      schema :savings_plans, infer: true
    end
  end
end
