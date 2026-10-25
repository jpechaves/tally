# auto_register: false
# frozen_string_literal: true

module Tally
  module Repos
    class TransactionRepo < Tally::DB::Repo
      # Transfers between people of the household (issue #21) that the statements don't
      # pair by themselves: a name-only Pix (issue #164), a Pix paying the other person's
      # Nubank card bill (issue #158).
      module Household
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
      end
    end
  end
end
