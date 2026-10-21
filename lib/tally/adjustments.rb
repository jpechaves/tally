# frozen_string_literal: true

module Tally
  # What you know about a row that its statement doesn't say (docs/architecture.md, section
  # 6): canceled, reimbursed or a different amount. The row itself stays as imported; the
  # report, budgets, cuts and planner count it through {.counted_amount}.
  module Adjustments
    KINDS = %w[canceled reimbursed amount_changed].freeze

    # How far from a purchase a row that paid it back can be, in days.
    REFUND_WINDOW = (-7..120)

    module_function

    # A transactions dataset with each row's adjustment joined as `adjustments`, and the
    # adjustment it pays back, if it is a linked refund, as `refund_links`.
    def join(dataset)
      dataset
        .left_join(Sequel[:transaction_adjustments].as(:adjustments), transaction_id: Sequel[:transactions][:id])
        .left_join(Sequel[:transaction_adjustments].as(:refund_links), refund_transaction_id: Sequel[:transactions][:id])
    end

    # What a row counts as, in cents, signed like the row (needs {.join}): nothing when it
    # was canceled or paid back a reimbursed purchase (it counts there), the amount net of
    # what came back when reimbursed, the real amount when it changed.
    def counted_amount
      amount = Sequel[:transactions][:amount_cents]
      adjusted = Sequel[:adjustments][:amount_cents]
      Sequel.case([
        [Sequel.~(Sequel[:refund_links][:id] => nil), 0],
        [{Sequel[:adjustments][:kind] => "canceled"}, 0],
        [{Sequel[:adjustments][:kind] => "reimbursed"}, Sequel.case([[amount < 0, amount + adjusted]], amount - adjusted)],
        [{Sequel[:adjustments][:kind] => "amount_changed"}, adjusted]
      ], amount)
    end

    # The columns a list of rows shows about adjustments (needs {.join}).
    def columns
      [
        counted_amount.as(:counted_cents),
        Sequel[:adjustments][:kind].as(:adjustment_kind),
        Sequel[:adjustments][:amount_cents].as(:adjustment_cents),
        Sequel[:adjustments][:refund_transaction_id],
        Sequel[:adjustments][:note].as(:adjustment_note),
        Sequel[:adjustments][:purchase_adjustment_id],
        Sequel[:refund_links][:transaction_id].as(:refunds_transaction_id)
      ]
    end

    # How an amount for a whole card purchase (its real total, or what came back) splits
    # over its installments (issue #69), the way the bank split the purchase: in proportion
    # to each installment, so the rounding cents stay where the bank put them. Installments
    # not imported yet weigh as much as the latest one.
    # @param series [Array<Hash>] the purchase's installment rows (InstallmentCalendar.series)
    # @return [Hash] installment number => cents, positive
    def purchase_shares(series, cents)
      Money.new(cents).allocate(installment_weights(series)).each_with_index.to_h { |share, index| [index + 1, share.cents] }
    end

    # What the purchase cost, in positive cents, as #purchase_shares counts it.
    def purchase_cents(series) = installment_weights(series).sum

    def installment_weights(series)
      latest = series.last
      by_number = series.to_h { [_1[:installment_number], _1[:amount_cents].abs] }
      (1..latest[:installment_total]).map { by_number.fetch(_1, latest[:amount_cents].abs) }
    end
    private_class_method :installment_weights

    # Ids of the rows of `dataset` that count as nothing: canceled, fully reimbursed, or
    # counted inside the purchase they paid back.
    def uncounted_ids(dataset)
      join(dataset.unordered).where(counted_amount => 0).select(Sequel[:transactions][:id])
    end
  end
end
