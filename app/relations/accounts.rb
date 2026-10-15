# frozen_string_literal: true

module Tally
  module Relations
    class Accounts < Tally::DB::Relation
      schema :accounts, infer: true
    end
  end
end
