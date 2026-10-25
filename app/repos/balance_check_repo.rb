# frozen_string_literal: true

module Tally
  module Repos
    # Balances the bank showed, typed in on the accounts page (Tally::Balances).
    class BalanceCheckRepo < Tally::DB::Repo
      # @return [Hash] account id => its checks, oldest first
      def by_account = balance_checks.dataset.order(:checked_on).all.group_by { _1[:account_id] }

      # One check per account and day: a new one replaces the old.
      def add(account_id:, checked_on:, balance_cents:)
        balance_checks.dataset.insert_conflict(target: %i[account_id checked_on], update: {balance_cents: Sequel[:excluded][:balance_cents]})
          .insert(account_id:, checked_on:, balance_cents:)
      end

      def delete(id) = balance_checks.dataset.where(id:).delete
    end
  end
end
