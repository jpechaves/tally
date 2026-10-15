# frozen_string_literal: true

module Tally
  module Repos
    class AccountRepo < Tally::DB::Repo
      def all = accounts.order(:name).to_a

      def find(id) = accounts.by_pk(id).one

      def by_name(name) = accounts.where(name:).one

      # The account with this name, created from Importers::ACCOUNTS the first time.
      def ensure(name)
        by_name(name) || begin
          defaults = Importers::ACCOUNTS.fetch(name) { raise ArgumentError, "unknown account #{name.inspect}" }
          accounts.dataset.insert(name:, **defaults)
          by_name(name)
        end
      end

      # Every account with its balance: opening balance plus the sum of its transactions.
      def with_balances
        balances = transactions.dataset.unordered.group_and_count(:account_id)
          .select_append { sum(:amount_cents).as(:sum_cents) }
          .to_h { [_1[:account_id], _1] }

        all.map do |account|
          stats = balances.fetch(account.id, {count: 0, sum_cents: 0})
          {account:, rows: stats[:count], balance_cents: account.opening_balance_cents + stats[:sum_cents].to_i}
        end
      end
    end
  end
end
