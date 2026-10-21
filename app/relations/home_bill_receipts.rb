# frozen_string_literal: true

module Tally
  module Relations
    class HomeBillReceipts < Tally::DB::Relation
      schema :home_bill_receipts, infer: true
    end
  end
end
