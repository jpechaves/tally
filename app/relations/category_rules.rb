# frozen_string_literal: true

module Tally
  module Relations
    class CategoryRules < Tally::DB::Relation
      schema :category_rules, infer: true
    end
  end
end
