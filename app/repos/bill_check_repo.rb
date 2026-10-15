# frozen_string_literal: true

module Tally
  module Repos
    # Cross-source checks on card bills (docs/statement-import.md, sections 2b and 7):
    #
    # - Nubank card: the bill's charges equal the account's "Pagamento de fatura" that paid
    #   it (found between 20 days before and 5 days after the due date).
    # - Itaú card: the bill's total equals the payment printed on the next bill, so the
    #   bills chain without gaps.
    #
    # Each check has a status ("ok", "warning", "unknown") and the difference in cents; the
    # page words them. `paid_by` is the paying account's name, or nil for the next bill.
    #
    # A difference is a warning, not an error: a bill can be paid partially, and IOF
    # rounding at the bank can leave a one-centavo gap.
    class BillCheckRepo < Tally::DB::Repo
      PAYMENT_WINDOW = (-20..5)
      NUBANK_ACCOUNT = "Nubank conta"

      def all
        names = accounts.to_a.to_h { [_1.id, _1.name] }
        statements = card_statements.dataset.order(:account_id, :due_on).all

        statements.group_by { _1[:account_id] }.flat_map do |account_id, bills|
          bills.each_with_index.map do |bill, index|
            paid_by, paid = if names[account_id] == "Nubank cartão"
              [NUBANK_ACCOUNT, account_payment(bill)]
            else
              [nil, bills[index + 1]&.fetch(:payments_cents)]
            end
            check(names[account_id], bill, paid_by, paid)
          end
        end
      end

      private

      def account_payment(bill)
        account = accounts.where(name: NUBANK_ACCOUNT).one or return nil
        due = Date.iso8601(bill[:due_on])
        rows = transactions.dataset.where(account_id: account.id, raw_description: "Pagamento de fatura")
          .where(occurred_on: (due + PAYMENT_WINDOW.begin).iso8601..(due + PAYMENT_WINDOW.end).iso8601)
        rows.empty? ? nil : -rows.sum(:amount_cents)
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
