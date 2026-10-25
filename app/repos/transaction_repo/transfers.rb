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

        # Transfers to or from someone of the household that point at no account yet, with
        # the counterparty's person (person_id).
        def household_one_legs
          transactions.dataset.where(kind: "transfer", transfer_id: nil, counter_account_id: nil)
            .join(:counterparties, id: :counterparty_id).where(Sequel[:counterparties][:is_self] => 1)
            .select_all(:transactions).select_append(Sequel[:counterparties][:person_id])
            .order(Sequel[:transactions][:id]).all
        end

        # Payments of a Nubank card bill ("Pagamento recebido") with no other side yet,
        # with the card owner's person_id.
        def unpaired_card_payments
          transactions.dataset.join(:accounts, id: :account_id)
            .where(ACCOUNTS[:template] => "Nubank cartão", TRANSACTIONS[:kind] => "transfer", TRANSACTIONS[:transfer_id] => nil)
            .where(TRANSACTIONS[:amount_cents] > 0)
            .select_all(:transactions).select_append(ACCOUNTS[:person_id])
            .order(TRANSACTIONS[:id]).all
        end

        # The Pix to Nubank's CNPJ that someone else of the household sent to pay this card
        # payment (issue #158): same amount, within a few days, still a purchase or already
        # pointing at the card. Closest date first.
        def bill_pix(payment, days: 5)
          transactions.dataset.join(:accounts, id: :account_id).join(:counterparties, id: TRANSACTIONS[:counterparty_id])
            .where(COUNTERPARTIES[:document] => Importers::NUBANK_CNPJ, TRANSACTIONS[:transfer_id] => nil)
            .exclude(ACCOUNTS[:person_id] => payment[:person_id])
            .where(TRANSACTIONS[:amount_cents] => -payment[:amount_cents], TRANSACTIONS[:occurred_on] => around(payment, -days..days))
            .where(Sequel.|({TRANSACTIONS[:kind] => "purchase"},
              Sequel.&({TRANSACTIONS[:kind] => "transfer"}, {TRANSACTIONS[:counter_account_id] => payment[:account_id]})))
            .select_all(:transactions)
            .order(closest_to(payment, TRANSACTIONS[:occurred_on]), TRANSACTIONS[:id])
            .first
        end

        # The other side of a transfer to someone of the household that names no bank (a
        # name-only Pix, issue #164): an unpaired transfer in one of that person's accounts,
        # same amount with the opposite sign, within a few days, pointing at no account or
        # back at this row's. Closest date first.
        def household_partner(row, person_id, days: 5)
          transactions.dataset
            .where(account_id: accounts.dataset.unordered.where(person_id:).select(:id), kind: "transfer", transfer_id: nil)
            .where(amount_cents: -row[:amount_cents], occurred_on: around(row, -days..days))
            .where(Sequel.|({counter_account_id: nil}, {counter_account_id: row[:account_id]}))
            .exclude(account_id: row[:account_id])
            .order(closest_to(row), :id)
            .first
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
