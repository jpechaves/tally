# frozen_string_literal: true

module Tally
  module Repos
    # Cross-source checks on card bills (docs/statement-import.md, sections 2b and 7):
    #
    # - Nubank card: the bill's charges equal what the account's "Pagamento de fatura" rows
    #   paid toward it (see #nubank_payments).
    # - Itaú card: the bill's total equals the payment printed on the next bill, so the
    #   bills chain without gaps.
    #
    # Each check has a status ("ok", "warning", "unknown") and the difference in cents; the
    # page words them. `paid_by` is the paying account's name, or nil for the next bill.
    #
    # A difference is a warning, not an error: a bill can be paid partially, and IOF
    # rounding at the bank can leave a one-centavo gap.
    class BillCheckRepo < Tally::DB::Repo
      # A payment made up to this many days after a bill's due date can still be extra
      # paid on that bill, when no newer bill is open to take it.
      LATE_DAYS = 5
      NUBANK_ACCOUNT = "Nubank conta"
      NUBANK_CARD = "Nubank cartão"

      def all
        names = accounts.to_a.to_h { [_1.id, _1.name] }
        statements = card_statements.dataset.order(:account_id, :due_on).all

        statements.group_by { _1[:account_id] }.flat_map do |account_id, bills|
          nubank = names[account_id] == NUBANK_CARD
          paid = nubank ? nubank_payments(bills) : bills.drop(1).map { _1[:payments_cents] } + [nil]
          bills.zip(paid).map do |bill, cents|
            check(names[account_id], bill, (NUBANK_ACCOUNT if nubank), cents)
          end
        end
      end

      private

      # What the account's "Pagamento de fatura" rows paid toward each bill, in bill order;
      # nil for a bill nothing paid.
      #
      # A bill can be paid in parts, some while it is still open, and money left after a
      # bill is paid in full goes toward the next one. So payments are taken in date order
      # and fill the oldest bill that still owes something among the bills open that day,
      # the rest moving on to the next. A bill opens on the previous bill's due date. A
      # payment on or before the day the first imported bill opened paid an older bill,
      # which is not imported. Money left with no open bill owing is extra on the newest
      # open bill, while it is at most LATE_DAYS past that bill's due date.
      def nubank_payments(bills)
        paid = bills.map { nil }
        account = accounts.where(name: NUBANK_ACCOUNT).one or return paid

        dues = bills.map { Date.iso8601(_1[:due_on]) }
        opens = [dues.first << 1, *dues[0...-1]]
        owed = bills.map { _1[:total_cents] }

        payments = transactions.dataset
          .where(account_id: account.id, raw_description: "Pagamento de fatura")
          .where { occurred_on > opens.first.iso8601 }
          .order(:occurred_on, :id).select_map([:occurred_on, :amount_cents])

        payments.each do |occurred_on, amount_cents|
          on = Date.iso8601(occurred_on)
          open = opens.each_index.select { |i| i.zero? || on >= opens[i] }
          left = -amount_cents
          next unless left.positive?

          open.each do |i|
            take = [owed[i], left].min
            next unless take.positive?

            owed[i] -= take
            paid[i] = paid[i].to_i + take
            left -= take
          end

          extra = open.reverse.find { on <= dues[_1] + LATE_DAYS }
          paid[extra] = paid[extra].to_i + left if left.positive? && extra
        end
        paid
      end

      def check(account, bill, paid_by, paid)
        total = bill[:total_cents]
        status = if paid.nil? then "unknown"
        elsif paid == total then "ok"
        else "warning"
        end

        {account:, due_on: bill[:due_on], total_cents: total, paid_by:, paid_cents: paid, status:,
         difference_cents: paid && (paid - total).abs}
      end
    end
  end
end
