# frozen_string_literal: true

module Tally
  module Repos
    # Home bills, who paid each month and their receipts (Tally::HomeBills, Tally::Receipts).
    class HomeBillRepo < Tally::DB::Repo
      BILLS = Sequel[:home_bills]
      TRANSACTIONS = Sequel[:transactions]

      # By name, with their category's name.
      def all = named.order(BILLS[:due_day], BILLS[:name]).all

      def find(id) = named.where(BILLS[:id] => id).first

      # A counterparty payee is kept by its match key, which a reset and re-import keep.
      def create(payee_key: nil, **attributes)
        id = payee_key.to_s[/\Acounterparty:(\d+)\z/, 1]
        payee_key = counterparties.dataset.where(id: id.to_i).get(Sequel.join(["match:", :match_key])) if id
        home_bills.dataset.insert(payee_key:, **attributes)
      end

      # The bill's payee as Tally::Insights.payee_key names it today, or nil.
      def payee_key(bill)
        key = bill[:payee_key]
        match_key = key.to_s[/\Amatch:(.+)\z/m, 1]
        return key unless match_key

        counterparties.dataset.where(match_key:).get(Sequel.join(["counterparty:", :id]))
      end

      # Deletes the bill with its payments and receipts.
      # @return [Array<String>] SHA-256 of receipt files no other bill-month uses any more
      def delete(id)
        shas = home_bill_receipts.dataset.where(home_bill_id: id).select_map(:sha256).uniq
        home_bills.dataset.where(id:).delete
        unused(shas)
      end

      # @return [Hash] [bill id, month] => payment
      def payments(bill_ids, months)
        home_bill_payments.dataset.where(home_bill_id: bill_ids, month: months).all.to_h { [[_1[:home_bill_id], _1[:month]], _1] }
      end

      # One payment per bill and month: a new one replaces the old.
      def pay(home_bill_id, month, **attributes)
        row = {home_bill_id:, month:, paid_by: nil, account_name: nil, external_id: nil}.merge(attributes)
        home_bill_payments.dataset.insert_conflict(target: %i[home_bill_id month], update: row.except(:home_bill_id, :month)
          .to_h { [_1, Sequel[:excluded][_1]] }).insert(row)
      end

      def unpay(home_bill_id, month) = home_bill_payments.dataset.where(home_bill_id:, month:).delete

      # What a row is known by across re-imports, what it paid, and who: its account's owner.
      def link(transaction_id)
        transactions.dataset.join(:accounts, id: TRANSACTIONS[:account_id]).left_join(:people, id: Sequel[:accounts][:person_id])
          .where(TRANSACTIONS[:id] => transaction_id)
          .select(Sequel[:accounts][:name].as(:account_name), TRANSACTIONS[:external_id], TRANSACTIONS[:occurred_on].as(:paid_on),
            Sequel.function(:abs, TRANSACTIONS[:amount_cents]).as(:amount_cents), Sequel[:people][:name].as(:paid_by)).first
      end

      # The rows payments are linked to, today, after any re-import.
      # @return [Hash] [account name, external id] => transaction id
      def linked(payments)
        keys = payments.select { _1[:external_id] }.map { [_1[:account_name], _1[:external_id]] }
        return {} if keys.empty?

        transactions.dataset.join(:accounts, id: TRANSACTIONS[:account_id])
          .where(Sequel.|(*keys.map { |name, external_id| {Sequel[:accounts][:name] => name, TRANSACTIONS[:external_id] => external_id} }))
          .select_map([Sequel[:accounts][:name], TRANSACTIONS[:external_id], TRANSACTIONS[:id]]).to_h { [_1.take(2), _1.last] }
      end

      # @return [Hash] [bill id, month] => receipts, oldest first
      def receipts(bill_ids)
        home_bill_receipts.dataset.where(home_bill_id: bill_ids).order(:id).all.group_by { [_1[:home_bill_id], _1[:month]] }
      end

      def receipt(id) = home_bill_receipts.dataset.where(id:).first

      def add_receipt(**attributes) = home_bill_receipts.dataset.insert(attributes)

      # @return [Array<String>] the receipt's SHA-256 if no other row uses that file
      def delete_receipt(receipt)
        home_bill_receipts.dataset.where(id: receipt[:id]).delete
        unused([receipt[:sha256]])
      end

      private

      def named
        home_bills.dataset.left_join(:categories, id: BILLS[:category_id])
          .select_all(:home_bills).select_append(Sequel[:categories][:name].as(:category_name))
      end

      def unused(shas) = shas - home_bill_receipts.dataset.where(sha256: shas).select_map(:sha256)
    end
  end
end
