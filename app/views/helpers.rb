# auto_register: false
# frozen_string_literal: true

module Tally
  module Views
    module Helpers
      # "R$ 1.234,56" / "-R$ 7,06"; blank for nil.
      def money(cents)
        cents.nil? ? "" : Tally::Money.new(cents).format
      end

      # "2026-09-02T10:11:12.123Z" -> "2026-09-02 10:11"
      def timestamp(text)
        text.to_s.sub("T", " ")[0, 16]
      end

      def source_label(source)
        Tally::Importers::SOURCES.fetch(source, source)
      end
    end
  end
end
