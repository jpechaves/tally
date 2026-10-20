# frozen_string_literal: true

require "cgi/escape"
require "open3"
require "tempfile"

module Tally
  module Importers
    class ItauCardPdf
      # The bill's words with their positions (`pdftotext -bbox`), grouped into the
      # columns of a page and the lines of a column.
      class Layout
        Word = Struct.new(:x_min, :y_min, :x_max, :y_max, :text)

        BBOX_WORD = /<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">(.*)<\/word>/

        # Some bills draw text with tight letter spacing, and poppler splits words into
        # fragments ("DAT A", "1.234 ,56"). On those, gaps inside a word measure 0.2-1.2 pt
        # and gaps between words 1.3 pt or more. Other bills have no fragments but put words
        # only 1.2 pt apart, so the join only happens on pages that look fragmented: many
        # gaps under FRAGMENT_GAP.
        JOIN_GAP = 1.25
        FRAGMENT_GAP = 1.0
        FRAGMENTED_SHARE = 0.2
        TOUCHING_GAP = 0.3
        # Words whose tops are this close (pt) are on the same line.
        LINE_TOLERANCE = 2.0

        def initialize(pdftotext)
          @pdftotext = pdftotext
        end

        # @return [Array<Array<Word>>] each page's words
        def pages(content)
          Tempfile.create(["itau", ".pdf"], binmode: true) do |file|
            file.write(content)
            file.flush
            output, error, status = Open3.capture3(@pdftotext, "-bbox", file.path, "-")
            raise Error.new(:pdftotext_failed, details: error.strip) unless status.success?

            parse_bbox(output.force_encoding(Encoding::UTF_8))
          end
        rescue Errno::ENOENT
          raise Error.new(:pdftotext_missing)
        end

        # Splits a page at its "DATA ... VALOR EM R$" column headers. A column runs from its
        # "DATA" to just past its "R$", so text beside the last column (limits, interest
        # rates) stays out of it. Pages without a header have no columns.
        def columns(words)
          headers = column_headers(words)

          headers.each_with_index.map do |data, index|
            following = headers[index + 1]
            right = [currency_right(words, data), following ? following.x_min - 5 : Float::INFINITY].min
            words.select { _1.x_min >= data.x_min - 12 && _1.x_min < right }
          end
        end

        # Groups words into lines, top to bottom, each line left to right.
        #
        # @return [Array<Array<String>>] each line's words
        def lines(words)
          words.sort_by { [_1.y_min, _1.x_min] }
            .slice_when { |a, b| b.y_min - a.y_min > LINE_TOLERANCE }
            .map { |line| merge_numbers(line.sort_by(&:x_min)) }
        end

        private

        def parse_bbox(html)
          pages = []
          html.each_line do |line|
            if line.include?("<page ")
              pages << []
            elsif (match = BBOX_WORD.match(line))
              pages.last << Word.new(*match.captures.first(4).map(&:to_f), CGI.unescapeHTML(match[5]))
            end
          end
          pages.map { rejoin(_1) }
        end

        # Glues word fragments that poppler split apart (see JOIN_GAP).
        def rejoin(words)
          rows = words.group_by { _1.y_min.round(1) }.values.map { |row| row.sort_by(&:x_min) }
          join_gaps = -0.01...(fragmented?(rows) ? JOIN_GAP : TOUCHING_GAP)

          rows.flat_map { |row| glue(row) { |previous, word| join_gaps.cover?(word.x_min - previous.x_max) } }
        end

        def fragmented?(rows)
          gaps = rows.flat_map { |row| row.each_cons(2).map { |a, b| b.x_min - a.x_max } }.select { (0...4).cover?(_1) }
          gaps.any? && gaps.count { _1 < FRAGMENT_GAP } > gaps.size * FRAGMENTED_SHARE
        end

        # "12.929" ",61" a little apart is still one amount.
        def merge_numbers(words)
          glue(words) do |previous, word|
            word.x_min - previous.x_max < 2.5 && word.text.match?(/\A[-\d.,]+\z/) && previous.text.match?(/\A-?[\d.,]+\z/)
          end.map(&:text)
        end

        # Joins each word to the one before it when the block says so.
        def glue(words)
          words.each_with_object([]) do |word, out|
            previous = out.last
            if previous && yield(previous, word)
              previous.text += word.text
              previous.x_max = word.x_max
            else
              out << word.dup
            end
          end
        end

        # The first "DATA" of each column, left to right.
        def column_headers(words)
          words.select { _1.text == "DATA" }.sort_by(&:x_min)
            .each_with_object([]) { |word, list| list << word if list.empty? || word.x_min - list.last.x_min > 40 }
        end

        # Just past the "R$" on the header's line, or no limit when there is none.
        def currency_right(words, data)
          currency = words.select { _1.text == "R$" && _1.x_min > data.x_max && (_1.y_min - data.y_min).abs < LINE_TOLERANCE }
            .min_by(&:x_min)
          currency ? currency.x_max + 10 : Float::INFINITY
        end
      end
    end
  end
end
