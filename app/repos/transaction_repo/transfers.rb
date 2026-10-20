# auto_register: false
# frozen_string_literal: true

module Tally
  module Repos
    class TransactionRepo < Tally::DB::Repo
      # The transfers between your accounts: their legs, pairing them, and the mirrored rows
      # of accounts without a statement of their own.
      module Transfers
        # Money moved into an account from your other accounts, oldest first, with what the
        # other leg paid in its own account's currency when the two are paired: a Conta Global
        # top-up is US$ 178,74 here and R$ 1.000,00 (other_cents, other_currency) in Nubank conta.
        #
        # @param through [String] the last day included, "YYYY-MM-DD"
        def top_ups(account_id, through:)
          legs = Sequel[:other_legs]
          others = Sequel[:other_accounts]
          transactions.dataset
            .where(TRANSACTIONS[:account_id] => account_id, TRANSACTIONS[:kind] => "transfer")
            .where((TRANSACTIONS[:amount_cents] > 0) & (TRANSACTIONS[:occurred_on] <= through))
            .left_join(TRANSACTIONS.as(:other_legs), Sequel.&({legs[:transfer_id] => TRANSACTIONS[:transfer_id]},
              Sequel.~(legs[:id] => TRANSACTIONS[:id])))
            .left_join(ACCOUNTS.as(:other_accounts), id: legs[:account_id])
            .select_all(:transactions)
            .select_append(
              legs[:amount_cents].as(:other_cents), others[:currency].as(:other_currency), others[:name].as(:other_account_name)
            )
            .order(TRANSACTIONS[:occurred_on], TRANSACTIONS[:id])
            .all
        end

        def unpaired_transfers
          transactions.dataset.where(kind: "transfer", transfer_id: nil).exclude(counter_account_id: nil)
            .order(:occurred_on, :id).all
        end

        def transfer_legs(transfer_id) = transactions.dataset.where(transfer_id:).order(:id).all

        # The other leg of a transfer between two imported accounts: same amount with the
        # opposite sign, pointing back at this account, within a few days.
        def find_partner(row, days: 5)
          transfers_back(row, days).where(amount_cents: -row[:amount_cents]).first
        end

        # Candidates for the other leg of a transfer between accounts in different currencies:
        # unpaired transfers in the other account, pointing back, with the opposite sign,
        # closest date first. Tally::Exchange decides which one it is.
        def exchange_partners(row, days: 3)
          amount = Sequel[:amount_cents]
          transfers_back(row, days).where(row[:amount_cents].negative? ? (amount > 0) : (amount < 0)).all
        end

        def create_transfer(occurred_on:, leg_ids:)
          id = transfers.dataset.insert(occurred_on:)
          transactions.dataset.where(id: leg_ids).update(transfer_id: id, updated_at: Repos.now)
          id
        end

        def delete_transfer(transfer_id)
          transactions.dataset.where(transfer_id:).update(transfer_id: nil, updated_at: Repos.now)
          transfers.dataset.where(id: transfer_id).delete
        end

        def delete_mirror(id)
          transactions.dataset.where(id:).where(Sequel.like(:external_id, "#{MIRROR_PREFIX}%")).delete
        end

        def mirror?(row) = row[:external_id].start_with?(MIRROR_PREFIX)

        def mirror_external_id(source_id) = "#{MIRROR_PREFIX}#{source_id}"

        private

        # Unpaired transfers in the row's other account that point back at it, within a few
        # days of it, closest date first.
        def transfers_back(row, days)
          transactions.dataset
            .where(account_id: row[:counter_account_id], counter_account_id: row[:account_id], kind: "transfer", transfer_id: nil)
            .where(occurred_on: around(row, -days..days))
            .exclude(id: row[:id])
            .order(closest_to(row), :id)
        end
      end
    end
  end
end
