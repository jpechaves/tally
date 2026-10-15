# frozen_string_literal: true

module Tally
  module Repos
    class CounterpartyRepo < Tally::DB::Repo
      BANK_FIELDS = %i[bank_name bank_code branch account_number].freeze

      def find(id) = counterparties.by_pk(id).one

      # Finds the counterparty by document + name, creating it the first time. Bank details
      # are kept up to date with the latest statement that has them.
      def upsert(name:, document: nil, document_kind: nil, **bank)
        match_key = self.class.match_key(name, document)
        existing = counterparties.where(match_key:).one
        bank = bank.slice(*BANK_FIELDS).compact

        if existing.nil?
          find(counterparties.dataset.insert(name:, document:, document_kind:, match_key:, **bank))
        elsif bank.any? { |field, value| existing[field] != value }
          counterparties.dataset.where(id: existing.id).update(**bank, updated_at: Repos.now)
          find(existing.id)
        else
          existing
        end
      end

      def self.match_key(name, document) = "#{document}|#{name.strip.squeeze(" ").upcase}"

      # Everyone you paid or were paid by, with how many rows and how much, biggest first.
      def with_totals
        counterparties.dataset.unordered
          .left_join(:transactions, counterparty_id: :id)
          .group(Sequel[:counterparties][:id])
          .select_all(:counterparties)
          .select_append { count(Sequel[:transactions][:id]).as(:rows) }
          .select_append { coalesce(sum(Sequel[:transactions][:amount_cents]), 0).as(:total_cents) }
          .order(Sequel.desc(:is_self), Sequel.function(:abs, Sequel.function(:coalesce, Sequel.function(:sum, Sequel[:transactions][:amount_cents]), 0)).desc)
          .to_a
      end

      def set_default_category(id, category_id)
        counterparties.dataset.where(id:).update(default_category_id: category_id, updated_at: Repos.now)
      end

      def set_self(id, value)
        counterparties.dataset.where(id:).update(is_self: value ? 1 : 0, updated_at: Repos.now)
      end
    end
  end
end
