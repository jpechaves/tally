# auto_register: false
# frozen_string_literal: true

module Tally
  module Views
    # The "me / partner / household" switch of the pages that add up spending (issue #21):
    # Home, Report, Cuts and Budgets. The action reads ?person= into person_id
    # (Tally::Action#person_param); the page shows that person's accounts, or the whole
    # household when there is no person or only one.
    module PersonSwitch
      def self.included(view)
        view.expose :people, decorate: false do
          Hanami.app["repos.person_repo"].all
        end

        view.expose :person, decorate: false do |people, person_id: nil|
          people.find { _1.id == person_id } if people.size > 1
        end

        # Transfers between two people of the household with no other side, which the
        # page warns about: they don't count, but a statement is probably missing.
        view.expose :unmatched_rows, decorate: false do
          Hanami.app["repos.transaction_repo"].totals(Tally::TransactionFilter.new(kind: "unmatched"))[:rows]
        end
      end
    end
  end
end
