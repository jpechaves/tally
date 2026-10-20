# frozen_string_literal: true

module Tally
  module Operations
    # Adds a category, or changes one: its name, nature, how far the planner may cut it,
    # and whether it is archived. Categories are archived, never deleted: old rows keep
    # them, but rules and the review list stop offering them.
    class SaveCategory < Tally::Operation
      include Deps["repos.category_repo", "operations.categorize"]

      # @param id [Integer, nil] nil to add one
      # @return [Integer] the category's id
      def call(name:, id: nil, parent_id: nil, kind: nil, nature: nil, max_cut_pct: nil, archived: false)
        name = name.to_s.strip.squeeze(" ")
        step Failure(:empty_name) if name.empty?

        existing = id && category_repo.find(id)
        step Failure(:not_found) if id && !existing
        # The form shows a starting category's name translated; saving it back keeps the stored one.
        name = existing[:name] if existing && Categories.shown_as(existing[:name]).include?(name)

        parent = parent_id && category_repo.find(parent_id)
        step Failure(:invalid_parent) if parent_id && (parent.nil? || parent[:parent_id])
        kind = if existing
          existing[:kind]
        else
          (parent ? parent[:kind] : kind)
        end
        step Failure(:invalid_kind) unless %w[expense income].include?(kind)

        nature = nil if kind == "income" || nature.to_s.empty?
        step Failure(:invalid_nature) if nature && !Categories::NATURES.include?(nature)
        max_cut_pct = nature ? (max_cut_pct || Categories::MAX_CUT_PCT.fetch(nature)) : nil
        step Failure(:invalid_max_cut) if max_cut_pct && !(0..100).cover?(max_cut_pct)

        transaction do
          if existing
            archived_at = archived ? (existing[:archived_at] || Repos.now) : nil
            category_repo.update(id, name:, nature:, max_cut_pct:, archived_at:)
            # Rules don't use archived categories, so rows they categorized go back to review.
            categorize.call if archived_at != existing[:archived_at]
            id
          else
            category_repo.create(name:, kind:, parent_id:, nature:, max_cut_pct:)
          end
        end
      rescue Sequel::UniqueConstraintViolation
        step Failure(:name_taken)
      end
    end
  end
end
