# auto_register: false
# frozen_string_literal: true

module Tally
  module Views
    # The accounts on the new and edit trip forms (trips/_form), by person of the household.
    module TripForm
      def self.included(view)
        view.expose :account_groups, decorate: false do
          people = person_repo.all
          accounts = account_repo.all.group_by { _1.person_id || people.first.id }
          people.map { [_1.name, accounts.fetch(_1.id, [])] }.reject { _1.last.empty? }
        end
      end

      # Where trip spending usually is, checked on a new trip: cards and accounts in another currency.
      def self.usual?(account) = account.kind == "credit_card" || account.currency != Tally::Money::DEFAULT_CURRENCY
    end
  end
end
