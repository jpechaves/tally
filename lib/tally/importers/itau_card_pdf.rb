# frozen_string_literal: true

module Tally
  module Importers
    # Itaú credit card bill (fatura) PDF.
    #
    # Page 1 holds the summary and the boleto; the next pages list the transactions in two
    # or three columns whose positions change from page to page. A plain text dump
    # interleaves the columns, so this reads every word with its position
    # (`pdftotext -bbox`, from poppler-utils), splits each page at its "DATA" column
    # headers, and reads each column top to bottom ({Layout}, {Reader}).
    #
    # The parsed rows must add up to the bill's printed totals to the cent, or the file is
    # rejected ({Bill}). See docs/statement-import.md, section 3.
    class ItauCardPdf
      SOURCE = "itau_card_pdf"
      ACCOUNT = "Itaú cartão"

      DAY_MONTH = /\A(\d\d)\/(\d\d)\z/
      FULL_DATE = /(\d\d)\/(\d\d)\/(\d{4})/
      AMOUNT = /\A-?\d{1,3}(?:\.\d{3})*,\d\d\z/
      INSTALLMENT = /\s?(\d\d)\/(\d\d)\z/

      def initialize(pdftotext: "pdftotext")
        @layout = Layout.new(pdftotext)
      end

      def call(_file_name, content)
        pages = @layout.pages(content)
        raise Error.new(:pdf_no_text) if pages.size < 2

        reader = Reader.new
        dates = reader.summary(@layout.lines(pages.first))
        pages.drop(1).flat_map { @layout.columns(_1) }.each { reader.column(@layout.lines(_1)) }

        Bill.new(reader.entries, reader.figures, dates).statement
      end
    end
  end
end
