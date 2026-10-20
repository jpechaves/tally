# frozen_string_literal: true

module Tally
  module Relations
    class HomeBillPayments < Tally::DB::Relation
      schema :home_bill_payments, infer: true
    end
  end
end
