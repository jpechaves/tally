# auto_register: false
# frozen_string_literal: true

module Tally
  module Repos
    class TransactionRepo < Tally::DB::Repo
      # What an import writes: the rows, the ones a new file no longer has, and the card
      # statements.
      module Writing
        def insert(attributes) = transactions.dataset.insert(attributes)

        def update(id, attributes)
          transactions.dataset.where(id:).update(**attributes, updated_at: Repos.now)
        end

        # Flags rows of this account that the new file no longer has (statement-import.md,
        # section 4, step 5). They are kept, never deleted.
        #
        # @param scope [Hash] {card_statement_id:} for a card bill, or {period: Range} for an
        #   account statement
        # @return [Integer] how many rows are now flagged
        def flag_missing(account_id:, import_id:, keep_ids:, card_statement_id: nil, period: nil)
          scope = transactions.dataset.where(account_id:, missing_since_import_id: nil)
            .exclude(id: keep_ids)
            .exclude(Sequel.like(:external_id, "#{MIRROR_PREFIX}%"))
          scope = if card_statement_id
            scope.where(card_statement_id:)
          else
            scope.where(card_statement_id: nil, occurred_on: period.begin.iso8601..period.end.iso8601)
          end

          scope.update(missing_since_import_id: import_id, updated_at: Repos.now)
        end

        # @return [Integer] the card statement's id
        def upsert_card_statement(account_id:, import_id:, figures:)
          attributes = figures.transform_values { _1.is_a?(Date) ? _1.iso8601 : _1 }.merge(import_id:)
          statements = card_statements.dataset
          existing = statements.where(account_id:, due_on: attributes[:due_on]).first

          if existing
            statements.where(id: existing[:id]).update(**attributes, updated_at: Repos.now)
            existing[:id]
          else
            statements.insert(account_id:, **attributes)
          end
        end

        def card_statements_for(account_id) = card_statements.dataset.where(account_id:).order(:due_on).all

        def card_statement(id) = card_statements.dataset.where(id:).first

        # Each card's latest bill, with what the bank says is already committed to the next
        # ones (Itaú prints it; Nubank's CSV doesn't).
        def card_statements_with_account
          latest = card_statements.dataset.unordered.group(:account_id).select { max(:due_on).as(:due_on) }.select_append(:account_id)
          card_statements.dataset
            .join(latest.as(:latest), account_id: :account_id, due_on: :due_on)
            .join(:accounts, id: Sequel[:card_statements][:account_id])
            .select_all(:card_statements).select_append(Sequel[:accounts][:name].as(:account_name))
            .order(Sequel[:accounts][:name]).all
        end
      end
    end
  end
end
