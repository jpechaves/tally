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

      # What Tally calls a counterparty (joined as `counterparties`): your display name if
      # you gave it one, else the bank's name. Matching and rules keep the bank's name.
      def self.counterparty_label
        Sequel.function(:coalesce, Sequel[:counterparties][:display_name], Sequel[:counterparties][:name])
      end

      # The counterparty columns a list of rows shows: its label as counterparty_name, the
      # bank's name under it, and your note.
      def self.counterparty_columns
        [
          counterparty_label.as(:counterparty_name),
          Sequel[:counterparties][:name].as(:counterparty_bank_name),
          Sequel[:counterparties][:note].as(:counterparty_note)
        ]
      end
    end
  end
end
