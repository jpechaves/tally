# frozen_string_literal: true

module Tally
  module Importers
    # What the card bill CSVs share (Nubank, XP): one file per bill, named after its due
    # date, with a header to check, one row per line and no total printed. A subclass sets
    # SOURCE, ACCOUNT, HEADER, COL_SEP, DUE_DATE (a pattern for the file name), the notice
    # keys HEADER_ERROR and FILE_NAME_ERROR, and #row and #summary.
    class CardBillCSV
      def call(file_name, content)
        type = self.class
        table = Text.table(content, col_sep: type::COL_SEP)
        unless table.headers == type::HEADER.split(type::COL_SEP)
          raise Error.new(type::HEADER_ERROR, header: type::HEADER.inspect)
        end

        due_on = due_date(file_name)
        rows = rows(table, due_on, warnings = [])
        dates = rows.flat_map { [_1.occurred_on, _1.purchased_on] }.compact
        Statement.new(
          source: type::SOURCE, account_name: type::ACCOUNT,
          period_start: dates.min, period_end: dates.max,
          rows:, card_statement: summary(rows, due_on), warnings:
        )
      end

      private

      def rows(table, due_on, warnings)
        repeats = Repeats.new
        rows = table.each.with_index(2).filter_map do |record, line|
          row(record, line, due_on, repeats, warnings)
        end
        raise Error.new(:bill_no_rows) if rows.empty?

        rows
      end

      def due_date(file_name)
        match = self.class::DUE_DATE.match(File.basename(file_name.to_s))
        raise Error.new(self.class::FILE_NAME_ERROR) unless match

        Date.iso8601(match[1])
      rescue Date::Error
        raise Error.new(:invalid_due_date)
      end

      # The row's charge (positive = money owed), or nil with a warning for a zero amount,
      # which is skipped.
      def charge(value, line, text, warnings)
        charge = Text.amount(value, line, decimal: ",")
        return charge unless charge.zero?

        warnings << Notice[:zero_amount_skipped, line:, text:]
        nil
      end
    end
  end
end
