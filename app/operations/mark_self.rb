# frozen_string_literal: true

module Tally
  module Operations
    # Marks a counterparty as you (or not) and re-reads its rows: a Pix between you and
    # yourself at another bank is a transfer, never spending or income
    # (statement-import.md, section 6, step 1).
    class MarkSelf < Tally::Operation
      include Deps[
        "repos.account_repo",
        "repos.counterparty_repo",
        "repos.transaction_repo",
        "operations.pair_transfers",
        "operations.categorize"
      ]

      def call(counterparty_id:, is_self:)
        counterparty = counterparty_repo.find(counterparty_id)
        step Failure(:not_found) unless counterparty

        transaction do
          counterparty_repo.set_self(counterparty.id, is_self)
          ids = transaction_repo.ids_for_counterparty(counterparty.id)
          account_ids = Hash.new { |known, name| known[name] = account_repo.ensure(name).id }
          transaction_repo.rows(ids).each { |row| update(row, counterparty, is_self, account_ids) }
          pair_transfers.call(touched_ids: ids)
          categorize.call(ids:)
        end

        counterparty_repo.find(counterparty.id)
      end

      private

      def update(row, counterparty, is_self, account_ids)
        if is_self && %w[purchase income].include?(row[:kind])
          counter = Importers.self_account_for(counterparty)
          transaction_repo.update(row[:id], kind: "transfer",
            counter_account_id: counter && account_ids[counter])
        elsif !is_self && row[:kind] == "transfer" && row[:counter_account_id] != row[:account_id]
          # Back to what the statement said. (A Pix no Crédito leg points at its own account
          # and stays a transfer.)
          transaction_repo.update(row[:id], kind: row[:amount_cents].negative? ? "purchase" : "income",
            counter_account_id: nil)
        end
      end
    end
  end
end
