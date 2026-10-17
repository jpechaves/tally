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

      # The newest applied import of the same statement: same account and source, and a
      # period within this one's (a copy with rows removed and another name has a shorter
      # period). The version of that statement in effect now.
      def latest_applied_like(import)
        imports.where(status: "applied", account_id: import.account_id, source: import.source)
          .where { (period_start >= import.period_start) & (period_end <= import.period_end) }
          .order(:id).last
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
