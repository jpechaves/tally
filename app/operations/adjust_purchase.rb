# frozen_string_literal: true

module Tally
  module Operations
    # One adjustment for every installment of a card purchase (issue #69), saved once for
    # the purchase and once on each installment (Tally::Adjustments), so the report and
    # the installment calendar count it as they count any adjustment.
    #
    # - canceled: every installment counts as nothing.
    # - reimbursed: `amount` came back for the whole purchase, split over its installments.
    # - amount_changed: the purchase's real total was `amount`, split over its installments.
    #
    # Installments imported later are adjusted as they arrive (#catch_up).
    class AdjustPurchase < Tally::Operation
      include Deps["repos.transaction_repo"]

      # @param row [Hash] the installment the adjustment was made from, already checked by
      #   AdjustTransaction
      # @param amount [Tally::Money, nil] for reimbursed and amount_changed
      def call(row:, kind:, amount: nil, note: nil)
        series = transaction_repo.installment_series(row[:id])
        step Failure(:not_installment) if series.empty?

        cents = step total_for(series, kind, amount)
        transaction do
          adjustment = transaction_repo.save_purchase_adjustment(row[:id], series_ids: series.map { _1[:id] }, kind:,
            amount_cents: cents, note:)
          apply(series, adjustment, series)
        end
        Success(row[:id])
      end

      # Adjusts the installments imported since each purchase was adjusted (ImportStatement).
      def catch_up
        transaction_repo.all_purchase_adjustments.each do |adjustment|
          series = transaction_repo.installment_series(adjustment[:transaction_id])
          fresh = series.select { _1[:id] > adjustment[:through_transaction_id] }
          next if fresh.empty?

          apply(series, adjustment, fresh)
          transaction_repo.update_purchase_adjustment(adjustment[:id], through_transaction_id: fresh.map { _1[:id] }.max)
        end
      end

      private

      def total_for(series, kind, amount)
        case kind
        when "canceled" then Success(nil)
        when "reimbursed"
          (amount&.positive? && amount.cents <= Adjustments.purchase_cents(series)) ? Success(amount.cents) : Failure(:invalid_reimbursed_amount)
        else
          # Every installment needs a real amount: a total of a few cents can't be split.
          fits = amount&.positive? && Adjustments.purchase_shares(series, amount.cents).values.all?(&:positive?)
          fits ? Success(amount.cents) : Failure(:invalid_adjusted_amount)
        end
      end

      # Saves the adjustment of each of `rows`, its share of the purchase's.
      def apply(series, adjustment, rows)
        shares = adjustment[:amount_cents] && Adjustments.purchase_shares(series, adjustment[:amount_cents])
        rows.each do |row|
          cents = shares&.fetch(row[:installment_number])
          # Nothing of a small reimbursement landed on this one.
          next if cents&.zero?

          cents *= (row[:amount_cents] <=> 0) if adjustment[:kind] == "amount_changed"
          transaction_repo.save_adjustment(row[:id], kind: adjustment[:kind], amount_cents: cents, note: adjustment[:note],
            purchase_adjustment_id: adjustment[:id])
        end
      end
    end
  end
end
