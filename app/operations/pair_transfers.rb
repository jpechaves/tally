# frozen_string_literal: true

module Tally
  module Operations
    # Links the two legs of each transfer between your own accounts (architecture.md,
    # section 6). Run it inside the caller's DB transaction.
    #
    # - Both accounts imported (Nubank conta "Pagamento de fatura" and the card's
    #   "Pagamento recebido"; the two account rows of a Pix no Crédito): the leg with the
    #   opposite amount in the other account, within a few days, becomes its partner.
    #   Between currencies (a Conta Global top-up and its BRL conversion) the amounts
    #   differ, and Tally::Exchange matches them through the printed rate.
    # - The other account has no statement (Itaú conta, Nubank RDB): a mirror row is
    #   written there, so that account's balance is right.
    # - Otherwise the row stays a one-leg transfer: still never spending or income. A Pix
    #   to someone of the household whose account wasn't imported yet finds it once it is
    #   (issue #21), and a name-only one finds the other person's side (issue #164).
    # - A Pix to Nubank that paid another household person's Nubank card bill pairs with
    #   the payment on that card (issue #158).
    class PairTransfers < Tally::Operation
      include Deps["repos.account_repo", "repos.transaction_repo"]

      # @param touched_ids [Array<Integer>] rows whose amount, date or kind may have
      #   changed since they were paired; their transfers are checked first
      # @return [Dry::Monads::Result] Success(number of transfers created)
      def call(touched_ids: [])
        currencies = account_repo.all.to_h { [_1.id, _1.currency] }
        find_counter_accounts
        touched_ids.each_slice(500) { |ids| transaction_repo.rows(ids).each { reconcile(_1, currencies) } }
        pair_all(currencies) + pay_household_bills
      end

      private

      def reconcile(row, currencies)
        return unless row[:transfer_id]

        legs = transaction_repo.transfer_legs(row[:transfer_id])
        other = legs.find { _1[:id] != row[:id] }
        exchange = other && currencies[other[:account_id]] != currencies[row[:account_id]]
        still_transfer = row[:kind] == "transfer" && row[:counter_account_id]

        if !still_transfer || (other && other[:account_id] != row[:counter_account_id])
          unlink(row[:transfer_id], legs)
        elsif exchange
          unlink(row[:transfer_id], legs) unless legs?(row, other, currencies)
        elsif other && transaction_repo.mirror?(other)
          if other[:amount_cents] != -row[:amount_cents] || other[:occurred_on] != row[:occurred_on]
            transaction_repo.update(other[:id], amount_cents: -row[:amount_cents], occurred_on: row[:occurred_on],
              description: row[:description], raw_description: row[:raw_description], last_import_id: row[:last_import_id])
          end
        elsif other && other[:amount_cents] != -row[:amount_cents]
          unlink(row[:transfer_id], legs)
        end
      end

      def find_counter_accounts
        ids = Hash.new do |known, (template, person_id, from)|
          known[[template, person_id, from]] = account_repo.counter_account_id(template, person_id, from:)
        end
        transaction_repo.household_one_legs.each do |row|
          if (template = Importers.account_at(row[:raw_description]))
            id = ids[[template, row[:person_id], row[:account_id]]]
            transaction_repo.update(row[:id], counter_account_id: id) if id
          elsif (partner = transaction_repo.household_partner(row, row[:person_id]))
            # A name-only Pix (issue #164): the other person's side says which account.
            transaction_repo.update(row[:id], counter_account_id: partner[:account_id])
            transaction_repo.update(partner[:id], counter_account_id: row[:account_id])
          end
        end
      end

      def unlink(transfer_id, legs)
        legs.each { transaction_repo.delete_mirror(_1[:id]) if transaction_repo.mirror?(_1) }
        transaction_repo.delete_transfer(transfer_id)
      end

      def pair_all(currencies)
        mirrored = account_repo.all.select { _1.mirror_transfers == 1 }.map(&:id)
        created = 0
        partners = Set.new # rows that became the partner of an earlier row in this loop

        transaction_repo.unpaired_transfers.each do |row|
          next if partners.include?(row[:id])

          if mirrored.include?(row[:counter_account_id])
            mirror_id = mirror(row)
            transaction_repo.create_transfer(occurred_on: row[:occurred_on], leg_ids: [row[:id], mirror_id])
            created += 1
          elsif (partner = partner(row, currencies))
            occurred_on = [row[:occurred_on], partner[:occurred_on]].min
            transaction_repo.create_transfer(occurred_on:, leg_ids: [row[:id], partner[:id]])
            partners << partner[:id]
            created += 1
          end
        end

        created
      end

      # A Pix to Nubank that paid someone else of the household's card bill (issue #158):
      # money sent to them, paired with the payment on their card.
      def pay_household_bills
        transaction_repo.unpaired_card_payments.count do |payment|
          pix = transaction_repo.bill_pix(payment) or next false
          pix_id = pix[:id]

          transaction_repo.update(pix_id, kind: "transfer", counter_account_id: payment[:account_id])
          transaction_repo.set_category(pix_id, category_id: nil, category_source: "none")
          transaction_repo.update(payment[:id], counter_account_id: pix[:account_id])
          transaction_repo.create_transfer(occurred_on: [pix[:occurred_on], payment[:occurred_on]].min, leg_ids: [pix_id, payment[:id]])
        end
      end

      def partner(row, currencies)
        if currencies[row[:account_id]] == currencies[row[:counter_account_id]]
          transaction_repo.find_partner(row)
        else
          transaction_repo.exchange_partners(row).find { legs?(row, _1, currencies) }
        end
      end

      def legs?(a, b, currencies)
        Tally::Exchange.legs?(a, b, currencies[a[:account_id]], currencies[b[:account_id]])
      end

      def mirror(row)
        external_id = transaction_repo.mirror_external_id(row[:id])
        attributes = {
          occurred_on: row[:occurred_on], amount_cents: -row[:amount_cents], kind: "transfer",
          counter_account_id: row[:account_id], description: row[:description],
          raw_description: row[:raw_description], last_import_id: row[:last_import_id]
        }

        if (existing = transaction_repo.by_external_id(row[:counter_account_id], external_id))
          transaction_repo.update(existing[:id], attributes)
          existing[:id]
        else
          transaction_repo.insert(account_id: row[:counter_account_id], external_id:,
            first_import_id: row[:last_import_id], **attributes)
        end
      end
    end
  end
end
