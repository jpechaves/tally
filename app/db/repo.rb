# frozen_string_literal: true

require "hanami/db/repo"

module Tally
  module DB
    class Repo < Hanami::DB::Repo
      # An amount column for a SUM in reais: the row's amount when its account (joined as
      # `accounts`) is in BRL, else NULL, so a dollar account's rows never add to a total.
      def self.in_reais(amount)
        Sequel.case([[{Sequel[:accounts][:currency] => Tally::Money::DEFAULT_CURRENCY}, amount]], nil)
      end
    end
  end
end
