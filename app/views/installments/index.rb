# frozen_string_literal: true

module Tally
  module Views
    module Installments
      class Index < Tally::View
        include Deps["repos.insight_repo", "repos.transaction_repo"]

        expose :rows, private: true, decorate: false do
          insight_repo.installment_rows
        end

        expose :all_cards, private: true, decorate: false do |rows|
          calendar_of(rows)
        end

        # The cards with installments left, as [id, name], for the switch (issue #163).
        expose :cards, decorate: false do |all_cards|
          all_cards.purchases.map { [_1.account_id, _1.account_name] }.uniq.sort_by(&:last)
        end

        # The card picked in the switch; nil for every card, or for a card with nothing left.
        expose :card, decorate: false do |cards, card_id: nil|
          card_id if cards.any? { _1.first == card_id }
        end

        expose :calendar do |rows, all_cards, card|
          card ? calendar_of(rows.select { _1[:account_id] == card }) : all_cards
        end

        expose :bills do |card|
          bills = transaction_repo.card_statements_with_account
          card ? bills.select { _1[:account_id] == card } : bills
        end

        private

        def calendar_of(rows) = Tally::InstallmentCalendar.new(rows, from: Date.today.strftime("%Y-%m"))
      end
    end
  end
end
