# frozen_string_literal: true

module Tally
  module Operations
    # What you know about a row that its statement doesn't say (Tally::Adjustments). The row
    # stays as imported; the adjustment is saved apart, so a re-import never undoes it.
    #
    # - canceled: the purchase was undone and counts as nothing.
    # - reimbursed: someone paid back `amount` (up to all of it), or the imported row
    #   `refund_id` did; that row then counts inside this one, not on its own.
    # - amount_changed: the real amount was `amount`, with the row's own sign.
    class AdjustTransaction < Tally::Operation
      include Deps["repos.transaction_repo"]

      # @param id [Integer] the row
      # @param kind [String] one of Tally::Adjustments::KINDS
      # @param amount [Tally::Money, nil] for reimbursed (without refund_id) and amount_changed
      # @param refund_id [Integer, nil] for reimbursed: the row that paid it back
      # @param note [String, nil]
      def call(id:, kind:, amount: nil, refund_id: nil, note: nil)
        row = transaction_repo.list(id:).first
        step Failure(:not_found) unless row
        step Failure(:not_adjustable) if row[:kind] == "transfer" || transaction_repo.refund_link(id)
        step Failure(:invalid_adjustment) unless Adjustments::KINDS.include?(kind)

        cents = step amount_for(row, kind, amount, refund_id)
        note = note.to_s.strip
        transaction_repo.save_adjustment(id, kind:, amount_cents: cents, refund_transaction_id: (refund_id if kind == "reimbursed"),
          note: note.empty? ? nil : note)
        Success(id)
      end

      private

      def amount_for(row, kind, amount, refund_id)
        case kind
        when "canceled" then Success(nil)
        when "reimbursed" then reimbursed(row, amount, refund_id)
        else
          return Failure(:invalid_adjusted_amount) unless amount&.positive?

          Success(row[:amount_cents].negative? ? -amount.cents : amount.cents)
        end
      end

      # What came back, positive, never more than the purchase.
      def reimbursed(row, amount, refund_id)
        return Failure(:not_reimbursable) unless row[:amount_cents].negative?

        if refund_id
          refund = transaction_repo.refund_candidates(row, limit: nil).find { _1[:id] == refund_id }
          refund ? Success(refund[:amount_cents]) : Failure(:invalid_refund)
        elsif amount && amount.positive? && amount.cents <= -row[:amount_cents]
          Success(amount.cents)
        else
          Failure(:invalid_reimbursed_amount)
        end
      end
    end
  end
end
