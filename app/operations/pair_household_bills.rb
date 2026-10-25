# frozen_string_literal: true

module Tally
  module Operations
    # A Pix to Nubank that paid someone else of the household's Nubank card bill (issue
    # #158) is money sent to them: it becomes a transfer to that card and pairs with the
    # payment there. Run by PairTransfers, inside the caller's DB transaction.
    class PairHouseholdBills < Tally::Operation
      include Deps["repos.transaction_repo"]

      # @return [Integer] how many bills it paired
      def call
        transaction_repo.unpaired_card_payments.count do |payment|
          pix = transaction_repo.bill_pix(payment) or next false

          pair(pix, payment)
        end
      end

      private

      def pair(pix, payment)
        pix_id, payment_id = pix[:id], payment[:id]
        transaction_repo.update(pix_id, kind: "transfer", counter_account_id: payment[:account_id])
        transaction_repo.set_category(pix_id, category_id: nil, category_source: "none")
        transaction_repo.update(payment_id, counter_account_id: pix[:account_id])
        transaction_repo.create_transfer(occurred_on: [pix[:occurred_on], payment[:occurred_on]].min, leg_ids: [pix_id, payment_id])
      end
    end
  end
end
