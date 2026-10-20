# frozen_string_literal: true

module Tally
  module Repos
    class AccountRepo < Tally::DB::Repo
      include Deps["repos.person_repo"]

      def all = accounts.order(:name).to_a

      def find(id) = accounts.by_pk(id).one

      # A person's account of this kind ("Nubank conta", one of Importers::ACCOUNTS), or nil.
      # @param person_id [Integer, nil] nil for you
      def by_template(template, person_id = nil)
        accounts.where(template:, person_id: person_id || person_repo.first.id).one
      end

      # A person's account of this kind, created from Importers::ACCOUNTS the first time.
      # @param person_id [Integer, nil] whose account; nil for you
      def ensure(template, person_id: nil)
        person_id ||= person_repo.first.id
        by_template(template, person_id) || begin
          defaults = Importers::ACCOUNTS.fetch(template) { raise ArgumentError, "unknown account #{template.inspect}" }
          accounts.dataset.insert(name: person_repo.account_name(template, person_id), template:, person_id:, **defaults)
          by_template(template, person_id)
        end
      end

      # Where a Pix to or from a person of the household went (issue #21): their account
      # of this kind, when it is imported, or created when that kind of account has no
      # statements and only mirrors its transfers (Itaú conta). Nil when there is none, or
      # when it is the row's own account.
      #
      # @param template [String, nil] the kind of account at the bank the row names
      #   (Importers.account_at); nil for a bank Tally doesn't know
      # @param person_id [Integer, nil] the counterparty's person; nil for you
      # @param from [Integer] the id of the row's account
      def counter_account_id(template, person_id, from:)
        return unless template

        account = by_template(template, person_id)
        account ||= self.ensure(template, person_id:) if Importers::ACCOUNTS.fetch(template)[:mirror_transfers] == 1
        account.id if account && account.id != from
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
