# frozen_string_literal: true

module Tally
  module Relations
    class TripAccounts < Tally::DB::Relation
      schema :trip_accounts, infer: true
    end
  end
end
