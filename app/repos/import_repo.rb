# frozen_string_literal: true

require "json"

module Tally
  module Repos
    class ImportRepo < Tally::DB::Repo
      def find(id) = imports.by_pk(id).one

      def recent(limit: 50) = imports.order { id.desc }.limit(limit).to_a

      def applied_with_sha(sha)
        imports.where(file_sha256: sha, status: "applied").order(:id).first
      end

      # Sources whose files are card bills: one file per bill (account and due date).
      CARD_SOURCES = [Tally::Importers::NubankCardCSV::SOURCE, Tally::Importers::ItauCardPdf::SOURCE].freeze

      # Whether the version of the statement in effect now came from these bytes (an
      # applied import's), so importing them again would change nothing.
      #
      # A card bill is known by its due date: it is in effect when its bill was last
      # written by a file with the same bytes. Bills can't go by period, because a bill's
      # period starts at its oldest installment's purchase date and may hold another bill's.
      def in_effect?(import)
        same_bytes = imports.dataset.where(file_sha256: import.file_sha256, status: "applied").select(:id)
        if CARD_SOURCES.include?(import.source)
          return card_statements.dataset.where(account_id: import.account_id, import_id: same_bytes).count.positive?
        end

        latest_applied_like(import).file_sha256 == import.file_sha256
      end

      # The newest applied import of the same statement: same account and source, and a
      # period within this one's (a copy with rows removed and another name has a shorter
      # period). The version of that statement in effect now.
      def latest_applied_like(import)
        imports.where(status: "applied", account_id: import.account_id, source: import.source)
          .where { (period_start >= import.period_start) & (period_end <= import.period_end) }
          .order(:id).last
      end

      def create(warnings: [], **attributes)
        id = imports.dataset.insert(**attributes, warnings: JSON.generate(warnings))
        find(id)
      end

      def update(id, warnings: nil, **attributes)
        attributes[:warnings] = JSON.generate(warnings) if warnings
        imports.dataset.where(id:).update(**attributes, updated_at: Repos.now)
        find(id)
      end

      def warnings(import) = JSON.parse(import.warnings)
    end
  end
end
