# frozen_string_literal: true

module Tally
  module Relations
    class HomeBills < Tally::DB::Relation
      schema :home_bills, infer: true
    end
  end
end
