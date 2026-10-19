# frozen_string_literal: true

module Tally
  module Relations
    class SubscriptionMarks < Tally::DB::Relation
      schema :subscription_marks, infer: true
    end
  end
end
