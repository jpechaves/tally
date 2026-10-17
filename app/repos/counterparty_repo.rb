# frozen_string_literal: true

module Tally
  module Repos
    class CounterpartyRepo < Tally::DB::Repo
      BANK_FIELDS = %i[bank_name bank_code branch account_number].freeze

      def find(id) = counterparties.by_pk(id).one

      # Finds the counterparty by document + name, creating it the first time. Bank details
      # are kept up to date with the latest statement that has them.
      #
      # A name without a document is a card merchant: its variants are one counterparty
      # (Tally::Merchants), named by their stable part. When a company with a CNPJ has
      # that same name (paid by Pix or boleto too), the merchant is that company.
      def upsert(name:, document: nil, document_kind: nil, **bank)
        match_key = self.class.match_key(name, document)
        existing = counterparties.where(match_key:).one ||
          (company(match_key) || cut_short(match_key) if document.nil?)
        bank = bank.slice(*BANK_FIELDS).compact

        if existing.nil?
          name = Tally::Merchants.stable_name(name) if document.nil?
          find(counterparties.dataset.insert(name:, document:, document_kind:, match_key:, **bank))
        elsif bank.any? { |field, value| existing[field] != value }
          counterparties.dataset.where(id: existing.id).update(**bank, updated_at: Repos.now)
          find(existing.id)
        else
          existing
        end
      end

      def self.match_key(name, document)
        document ? "#{document}|#{name.strip.squeeze(" ").upcase}" : "|#{Tally::Merchants.key(name)}"
      end

      # Everyone you paid or were paid by, with how many rows and how much in reais (rows in
      # a dollar account count, but their amounts don't add to the total): you first, then
      # biggest first (ties by id, so pages never shuffle).
      #
      # @param search [String, nil] part of the name, any accents or case (Tally::Search)
      def with_totals(search: nil, limit: nil, offset: nil)
        total = Sequel.function(:coalesce, Sequel.function(:sum, Tally::DB::Repo.in_reais(Sequel[:transactions][:amount_cents])), 0)
        named(search)
          .left_join(:transactions, counterparty_id: :id)
          .left_join(:accounts, id: Sequel[:transactions][:account_id])
          .group(Sequel[:counterparties][:id])
          .select_all(:counterparties)
          .select_append { count(Sequel[:transactions][:id]).as(:rows) }
          .select_append(total.as(:total_cents))
          .order(
            Sequel.desc(:is_self),
            Sequel.function(:abs, total).desc,
            Sequel[:counterparties][:id]
          )
          .limit(limit, offset)
          .to_a
      end

      # Card merchants (no document) that are the same as a company with a CNPJ, by name
      # (Tally::Merchants.key), become that company: their rows move to it, and so does
      # their default category when the company has none. You and your own accounts are
      # left alone.
      #
      # @return [Array<Integer>] the ids of the rows that moved
      def link_merchants
        moved = []
        counterparties.dataset.where(document: nil, is_self: 0).order(:id).all.each do |merchant|
          target = company(merchant[:match_key]) or next

          ids = transactions.dataset.where(counterparty_id: merchant[:id]).select_map(:id)
          transactions.dataset.where(id: ids).update(counterparty_id: target.id, updated_at: Repos.now)
          if target.default_category_id.nil? && merchant[:default_category_id]
            set_default_category(target.id, merchant[:default_category_id])
          end
          counterparties.dataset.where(id: merchant[:id]).delete
          moved.concat(ids)
        end
        moved
      end

      # How many counterparties the search finds.
      def count(search: nil) = named(search).count

      def set_default_category(id, category_id)
        counterparties.dataset.where(id:).update(default_category_id: category_id, updated_at: Repos.now)
      end

      def set_self(id, value)
        counterparties.dataset.where(id:).update(is_self: value ? 1 : 0, updated_at: Repos.now)
      end

      private

      def named(search)
        scope = counterparties.dataset.unordered
        folded = Tally::Search.fold(search.to_s)
        return scope if folded.empty?

        pattern = "%#{scope.escape_like(folded)}%"
        scope.where(Sequel.like(Sequel.function(Tally::Search::FUNCTION, Sequel[:counterparties][:name]), pattern))
      end

      # The company with a CNPJ, not you, whose name has this merchant key ("|KEY"); the
      # oldest if several do.
      def company(match_key)
        key = match_key.delete_prefix("|")
        counterparties.dataset.where(document_kind: "cnpj", is_self: 0)
          .where(Sequel.function(Tally::Merchants::KEY_FUNCTION, :name) => key)
          .order(:id).first&.then { find(_1[:id]) }
      end

      # A merchant whose name another bank cut shorter, or longer: one key starts with the
      # other, and the shorter has at least Merchants::MIN_PREFIX characters.
      def cut_short(match_key)
        key = match_key.delete_prefix("|")
        return if key.length < Tally::Merchants::MIN_PREFIX

        counterparties.dataset.where(document: nil)
          .where(Sequel.lit("length(match_key) > ?", Tally::Merchants::MIN_PREFIX))
          .where(Sequel.lit("? LIKE substr(match_key, 2) || '%' OR match_key LIKE ?", key, "|#{key}%"))
          .order(:id).first&.then { find(_1[:id]) }
      end
    end
  end
end
