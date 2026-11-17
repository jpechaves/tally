# frozen_string_literal: true

module Tally
  module Repos
    # Cross-source checks on card bills (docs/statement-import.md, sections 2b and 7):
    #
    # - Nubank card: the bill's charges equal what the account's "Pagamento de fatura" rows
    #   paid toward it (see #nubank_payments).
    # - XP card: the same, with the "Pagamento de fatura" rows the bills themselves list
    #   (a bill can list the previous bill's payment too, so they go by date, not by file).
    # - Itaú card: the bill's total equals the payment printed on the next bill, so the
    #   bills chain without gaps.
    #
    # Each check has a status ("ok", "open", "warning", "unknown") and the difference in
    # cents; the page words them. `paid_by` is the paying account's name, or nil for the next bill.
    #
    # A difference is a warning, not an error: a bill can be paid partially, and IOF
    # rounding at the bank can leave a one-centavo gap.
    class BillCheckRepo < Tally::DB::Repo
      # A payment made up to this many days after a bill's due date still pays that bill.
      LATE_DAYS = 5
      NUBANK_ACCOUNT = "Nubank conta"
      NUBANK_CARD = "Nubank cartão"
      XP_CARD = "XP cartão"
      PAYMENT = "Pagamento de fatura"

      def all
        all_accounts = accounts.to_a
        names = all_accounts.to_h { [_1.id, _1.name] }
        xp = all_accounts.select { _1.template == XP_CARD }.map(&:id)
        statements = card_statements.dataset.order(:account_id, :due_on).all

        statements.group_by { _1[:account_id] }.flat_map do |account_id, bills|
          paid_by, paid = paid(names[account_id], xp.include?(account_id) && account_id, bills)
          bills.zip(paid).map { |bill, cents| check(names[account_id], bill, paid_by, cents) }
        end
      end

      private

      # Who paid the bills and what went toward each: see the class comment.
      def paid(name, xp_card, bills)
        if name == NUBANK_CARD
          [NUBANK_ACCOUNT, nubank_payments(bills)]
        elsif xp_card
          ["XP conta", payments_toward(bills, payments(xp_card, bills, 1))]
        else
          [nil, bills.drop(1).map { _1[:payments_cents] } + [nil]]
        end
      end

      def nubank_payments(bills)
        account = accounts.where(name: NUBANK_ACCOUNT).one or return bills.map { nil }

        payments_toward(bills, payments(account.id, bills, -1))
      end

      # An account's "Pagamento de fatura" rows that may pay these bills, as [date, cents
      # paid]; sign is the sign of a payment in that account (-1 leaving a checking account,
      # +1 arriving on a card).
      #
      # A payment on or before the day the first imported bill opened (the month before
      # its due date) paid an older bill, which is not imported.
      def payments(account_id, bills, sign)
        opened = Date.iso8601(bills.first[:due_on]) << 1
        transactions.dataset
          .where(account_id:, raw_description: PAYMENT)
          .where { occurred_on > opened.iso8601 }
          .order(:occurred_on, :id).select_map([:occurred_on, :amount_cents])
          .map { |occurred_on, cents| [occurred_on, sign * cents] }
      end

      # What the payments paid toward each bill, in bill order; nil for a bill nothing paid.
      #
      # A payment pays the bill it was made for: the first bill due on or after its date,
      # or due at most LATE_DAYS before it (paid a little late). A bill can be paid in
      # parts, some while it is still open. Money above what that bill still owes goes to
      # the next bills, and what is left after the newest one is extra on it. A payment
      # never fills an older bill, so a bill paid short keeps its own difference.
      def payments_toward(bills, payments)
        paid = bills.map { nil }
        dues = bills.map { Date.iso8601(_1[:due_on]) }
        owed = bills.map { _1[:total_cents] }

        payments.each do |occurred_on, left|
          on = Date.iso8601(occurred_on)
          first = dues.index { on <= _1 + LATE_DAYS }
          next unless first && left.positive?

          (first...bills.size).each do |i|
            take = [owed[i], left].min
            next unless take.positive?

            owed[i] -= take
            paid[i] = paid[i].to_i + take
            left -= take
          end

          paid[-1] = paid[-1].to_i + left if left.positive?
        end
        paid
      end

      # A bill not due yet is open: paying it in parts is normal, so it isn't a warning
      # before its due date, unless it was paid more than its total.
      def check(account, bill, paid_by, paid)
        total = bill[:total_cents]
        status = if paid == total then "ok"
        elsif bill[:due_on] > Date.today.iso8601 && paid.to_i < total then "open"
        elsif paid.nil? then "unknown"
        else "warning"
        end

        {account:, due_on: bill[:due_on], total_cents: total, paid_by:, paid_cents: paid, status:,
         difference_cents: paid && (paid - total).abs}
      end
    end
  end
end
