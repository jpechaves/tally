# frozen_string_literal: true

module Tally
  module Relations
    class PurchaseAdjustments < Tally::DB::Relation
      schema :purchase_adjustments, infer: true
    end
  end
end
