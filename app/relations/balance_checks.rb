# frozen_string_literal: true

module Tally
  module Relations
    class BalanceChecks < Tally::DB::Relation
      schema :balance_checks, infer: true
    end
  end
end
