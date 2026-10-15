# auto_register: false
# frozen_string_literal: true

module Tally
  module Views
    module Helpers
      # "R$ 1.234,56" / "-R$ 7,06"; blank for nil.
      def money(cents)
        cents.nil? ? "" : Tally::Money.new(cents).format
      end

      # 123456 -> "1234,56", for a form field that Money.parse reads back exactly.
      def amount_field(cents)
        units, rest = cents.abs.divmod(100)
        "#{"-" if cents.negative?}#{units},#{rest.to_s.rjust(2, "0")}"
      end

      # "2026-09-02T10:11:12.123Z" -> "2026-09-02 10:11"
      def timestamp(text)
        text.to_s.sub("T", " ")[0, 16]
      end

      # The categories for a <select>, as [[parent label, [[id, name], ...]], ...]: each
      # parent first in its own group, then its children. Archived ones are left out.
      def category_groups(tree)
        active = tree.reject { _1[:archived_at] }
        active.reject { _1[:parent_id] }.map do |parent|
          children = active.select { _1[:parent_id] == parent[:id] }
          [parent[:name], [[parent[:id], "#{parent[:name]} (all)"]] + children.map { [_1[:id], _1[:name]] }]
        end
      end

      def category_label(row)
        return "" unless row[:category_name]

        row[:category_source] == "bank" ? "#{row[:category_name]}?" : row[:category_name]
      end

      def source_label(source)
        Tally::Importers::SOURCES.fetch(source, source)
      end
    end
  end
end
