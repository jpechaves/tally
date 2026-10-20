# frozen_string_literal: true

module Tally
  module Operations
    # Marks a counterparty as someone of the household (or no one) and re-reads its rows:
    # a Pix between you and yourself at another bank, or between you and your partner, is
    # a transfer, never spending or income (statement-import.md, section 6, step 1;
    # issue #21).
    class MarkSelf < Tally::Operation
      include Deps[
        "repos.account_repo",
        "repos.counterparty_repo",
        "repos.person_repo",
        "repos.transaction_repo",
        "operations.pair_transfers",
        "operations.categorize"
      ]

      # @param person_id [Integer, nil] who the counterparty is; nil for no one
      def call(counterparty_id:, person_id:)
        counterparty = counterparty_repo.find(counterparty_id)
        step Failure(:not_found) if counterparty.nil? || (person_id && !person_repo.find(person_id))

        transaction do
          counterparty_repo.set_person(counterparty.id, person_id)
          ids = transaction_repo.ids_for_counterparty(counterparty.id)
          counter_ids = Hash.new do |known, (template, from)|
            known[[template, from]] = account_repo.counter_account_id(template, person_id, from:)
          end
          transaction_repo.rows(ids).each { |row| update(row, person_id, counter_ids) }
          pair_transfers.call(touched_ids: ids)
          categorize.call(ids:)
        end

        counterparty_repo.find(counterparty.id)
      end

      private

      def update(row, person_id, counter_ids)
        # A transfer the mark made, not one the statement says (a Pix no Crédito leg points
        # at its own account and stays a transfer).
        marked = row[:kind] == "transfer" && row[:counter_account_id] != row[:account_id]

        if person_id && (marked || %w[purchase income].include?(row[:kind]))
          transaction_repo.update(row[:id], kind: "transfer",
            counter_account_id: counter_ids[[Importers.account_at(row[:raw_description]), row[:account_id]]])
        elsif !person_id && marked
          # Back to what the statement said.
          transaction_repo.update(row[:id], kind: row[:amount_cents].negative? ? "purchase" : "income",
            counter_account_id: nil)
        end
      end
    end
  end
end
