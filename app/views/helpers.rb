# auto_register: false
# frozen_string_literal: true

module Tally
  module Views
    # Formatting in the reader's language: amounts, dates, months and the app's own codes
    # (kinds, natures, statuses). The text itself lives in config/i18n.
    module Helpers
      # Cut suggestions whose :name is a category (the others name a payee).
      CATEGORY_SIGNALS = %w[big growth].freeze

      def locale = _context.i18n.locale.to_s

      # "R$ 1.234,56" / "-R$ 7,06" in Portuguese, "R$ 1,234.56" in English; blank for nil.
      def money(cents)
        cents.nil? ? "" : Tally::Money.new(cents).format(locale)
      end

      # 123456 -> "1234,56" ("1234.56" in English), for a form field the action reads back
      # exactly with the same decimal mark.
      def amount_field(cents)
        Tally::Money.new(cents).to_field(locale)
      end

      # 12.5 -> "12,5" in Portuguese.
      def number(value)
        value.to_s.tr(".", Tally::Money.decimal_mark(locale))
      end

      # "2026-09-02" -> "02/09/2026" / "Sep 2, 2026"; blank for nil.
      def date(text)
        text.nil? ? "" : l(Date.iso8601(text.to_s[0, 10]), format: :day)
      end

      # "2026-09" -> "set/2026" / "Sep 2026"
      def month_label(month)
        l(Date.new(month[0, 4].to_i, month[5, 2].to_i, 1), format: :month)
      end

      # "2026-09-02T10:11:12.123Z" -> "02/09/2026 10:11"
      def timestamp(text)
        text = text.to_s
        "#{date(text)} #{text[11, 5]}".strip
      end

      # The categories for a <select>, as [[parent label, [[id, name], ...]], ...]: each
      # parent first in its own group, then its children. Archived ones are left out.
      def category_groups(tree)
        active = tree.reject { _1[:archived_at] }
        active.reject { _1[:parent_id] }.map do |parent|
          children = active.select { _1[:parent_id] == parent[:id] }
          name = category_name(parent[:name])
          [name, [[parent[:id], t("categories.all", name:)]] + children.map { [_1[:id], category_name(_1[:name])] }]
        end
      end

      # A starting category's name in the current language; one you named yourself as typed.
      def category_name(name) = name && Tally::Categories.display(name, locale)

      # "Moradia › Energia", translated like category_name.
      def category_path(parent_name, name) = [parent_name, name].compact.map { category_name(_1) }.join(" › ")

      def category_label(row)
        return "" unless row[:category_name]

        name = category_name(row[:category_name])
        row[:category_source] == "bank" ? "#{name}?" : name
      end

      def source_label(source) = t("sources.#{source}", default: source.to_s)

      def kind_label(kind) = t("kinds.#{kind}", default: kind.to_s)

      def nature_label(nature) = t("natures.#{nature || "unset"}", default: nature.to_s)

      def status_label(group, status) = t("statuses.#{group}.#{status}", default: status.to_s)

      # A cut suggestion's title or detail, worded from its facts (Tally::Cuts).
      def cut_text(suggestion, part)
        facts = suggestion.facts.to_h do |key, value|
          [key, case [key, value]
                in [:cents | :average_cents | :later_cents, _] then money(value)
                in [:from | :to, _] then month_label(value)
                in [:dates, _] then value.map { date(_1) }.join(", ")
                in [:name, _] if CATEGORY_SIGNALS.include?(suggestion.signal) then category_name(value)
                in [_, Array] then value.join(", ")
                in [_, Float] then number(value)
                else value
                end]
        end
        facts[:purchases] = t("cuts.purchases", count: suggestion.facts[:count]) if suggestion.facts.key?(:count)
        t("cuts.signals.#{suggestion.signal}.#{part}", **facts)
      end
    end
  end
end
