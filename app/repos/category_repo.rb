# frozen_string_literal: true

module Tally
  module Repos
    # Categories, as plain hashes. Two levels: a parent ("Moradia") and its categories
    # ("Energia"); rows can sit on either.
    class CategoryRepo < Tally::DB::Repo
      def find(id) = categories.dataset.where(id:).first

      def empty? = categories.dataset.empty?

      # Every category, expenses first, each parent followed by its children, with a
      # `label` like "Moradia › Energia" and how many transactions use it.
      def tree(include_archived: false)
        scope = categories.dataset
        scope = scope.where(archived_at: nil) unless include_archived
        rows = scope.all
        # Totals in reais: rows in a dollar account count, but their amounts don't add up here.
        usage = transactions.dataset.unordered.exclude(category_id: nil)
          .join(:accounts, id: Sequel[:transactions][:account_id])
          .group_and_count(Sequel[:transactions][:category_id])
          .select_append(Sequel.function(:sum, Tally::DB::Repo.in_reais(Sequel[:transactions][:amount_cents])).as(:total_cents))
          .to_h { [_1[:category_id], _1] }
        names = categories.dataset.select_hash(:id, :name)

        rows.each do |row|
          row[:parent_name] = names[row[:parent_id]]
          row[:label] = [row[:parent_name], row[:name]].compact.join(" › ")
          row[:rows] = usage.dig(row[:id], :count) || 0
          row[:total_cents] = usage.dig(row[:id], :total_cents) || 0
        end
        rows.sort_by { [_1[:kind], Categories.fold(_1[:parent_name] || _1[:name]), _1[:parent_id] ? 1 : 0, Categories.fold(_1[:name])] }
      end

      # id => kind ("expense" | "income") of the categories rules may use: not archived.
      def kinds = categories.dataset.where(archived_at: nil).select_hash(:id, :kind)

      # Child names are unique in the seeds, so a name finds one category. A child wins
      # over a parent of the same name.
      def id_by_name(name)
        categories.dataset.where(name:).order(Sequel.desc(Sequel.function(:coalesce, :parent_id, 0))).get(:id)
      end

      def find_by(name:, parent_id:) = categories.dataset.where(name:, parent_id:).first

      def create(name:, kind:, parent_id: nil, nature: nil, max_cut_pct: nil)
        if kind == "expense" && nature
          max_cut_pct ||= Categories::MAX_CUT_PCT.fetch(nature)
        end
        categories.dataset.insert(name:, kind:, parent_id:, nature:, max_cut_pct:)
      end

      def update(id, **attributes)
        categories.dataset.where(id:).update(**attributes, updated_at: Repos.now)
      end
    end
  end
end
