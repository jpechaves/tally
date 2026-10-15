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

      # The newest applied import of the same account and period (a card bill, or an
      # account statement's dates): the version of that statement in effect now.
      def latest_applied_like(import)
        imports.where(status: "applied", account_id: import.account_id, period_start: import.period_start,
          period_end: import.period_end).order(:id).last
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
