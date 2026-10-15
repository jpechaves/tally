# frozen_string_literal: true

module Tally
  module Relations
    class DismissedSuggestions < Tally::DB::Relation
      schema :dismissed_suggestions, infer: true
    end
  end
end
