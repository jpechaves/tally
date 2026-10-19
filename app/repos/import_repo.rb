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

      # Sources whose files cover the whole period in their name, days with no rows
      # included. Conta Global files only span their first and last rows, so a quiet week
      # between two of them is not a missing file.
      PERIOD_SOURCES = [Tally::Importers::NubankAccountCSV::SOURCE].freeze

      # The statements missing between the ones imported, by account (Tally::StatementGaps).
      #
      # @return [Hash{Integer => Array<StatementGaps::Gap>}] only accounts with a gap
      def gaps
        periods = imports.dataset.where(status: "applied", source: PERIOD_SOURCES).exclude(period_start: nil)
          .select_map([:account_id, :period_start, :period_end])
          .group_by(&:first).transform_values { |rows| rows.map { Date.iso8601(_1[1])..Date.iso8601(_1[2]) } }
        dues = card_statements.dataset.select_map([:account_id, :due_on])
          .group_by(&:first).transform_values { |rows| rows.map { Date.iso8601(_1[1]) } }

        periods.transform_values { StatementGaps.statements(_1) }
          .merge(dues.transform_values { StatementGaps.bills(_1) }) { |_, a, b| a + b }
          .reject { _2.empty? }
      end

      # @param warnings [Array<Importers::Notice>]
      # @param error [Importers::Notice, nil]
      def create(warnings: [], error: nil, **attributes)
        id = imports.dataset.insert(**attributes, warnings: dump(warnings), error: error && JSON.generate(error.to_h))
        find(id)
      end

      def update(id, warnings: nil, **attributes)
        attributes[:warnings] = dump(warnings) if warnings
        imports.dataset.where(id:).update(**attributes, updated_at: Repos.now)
        find(id)
      end

      # The import's warnings as Importers::Notice, or the English text older imports kept.
      def warnings(import) = JSON.parse(import.warnings).map { Tally::Importers::Notice.load(_1) }

      # Why the import was rejected (Importers::Notice, or older English text), or nil.
      def error(import)
        text = import.error or return nil
        text.start_with?("{") ? Tally::Importers::Notice.load(JSON.parse(text)) : text
      end

      private

      def dump(warnings) = JSON.generate(warnings.map { _1.is_a?(Tally::Importers::Notice) ? _1.to_h : _1 })
    end
  end
end
