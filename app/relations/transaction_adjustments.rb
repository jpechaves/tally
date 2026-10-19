# frozen_string_literal: true

module Tally
  module Relations
    class TransactionAdjustments < Tally::DB::Relation
      schema :transaction_adjustments, infer: true
    end
  end
end
