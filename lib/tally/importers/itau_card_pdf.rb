# frozen_string_literal: true

require "cgi/escape"
require "open3"
require "tempfile"

module Tally
  module Importers
    # Itaú credit card bill (fatura) PDF.
    #
    # Page 1 holds the summary and the boleto; the next pages list the transactions in two
    # or three columns whose positions change from page to page. A plain text dump
    # interleaves the columns, so this reads every word with its position
    # (`pdftotext -bbox`, from poppler-utils), splits each page at its "DATA" column
    # headers, and reads each column top to bottom.
    #
    # The parsed rows must add up to the bill's printed totals to the cent, or the file is
    # rejected. See docs/statement-import.md, section 3.
    class ItauCardPdf
      SOURCE = "itau_card_pdf"
      ACCOUNT = "Itaú cartão"

      Word = Struct.new(:x_min, :y_min, :x_max, :y_max, :text)

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

      DAY_MONTH = /\A(\d\d)\/(\d\d)\z/
      FULL_DATE = /(\d\d)\/(\d\d)\/(\d{4})/
      AMOUNT = /\A-?\d{1,3}(?:\.\d{3})*,\d\d\z/
      INSTALLMENT = /\s?(\d\d)\/(\d\d)\z/

      # Section headings, compared with spaces removed (fragments make spacing unreliable).
      SECTIONS = {
        "Pagamentosefetuados" => :payments,
        "Lançamentos:comprasesaques" => :purchases,
        "Lançamentos:produtoseserviços" => :fees,
        "Comprasparceladas" => :future,
        "Limitesdecrédito" => :other,
        "Encargoscobradosnestafatura" => :other,
        "Novotetodejuros" => :other,
        "Simulação" => :other,
        "Fiqueatento" => :other
      }.freeze

      # Printed figures, by label (spaces removed). The value is the last amount on the line.
      LABELS = {
        "Totaldafaturaanterior" => :previous_total,
        "Totaldestafatura" => :total,
        "Lançamentosatuais" => :current,
        "Totaldoslançamentosatuais" => :current,
        "Totaldospagamentos" => :payments,
        "Lançamentosnocartão" => :purchases,
        "Lançamentosprodutoseserviços" => :fees,
        "Próximafatura" => :next_statement,
        "Demaisfaturas" => :later_statements,
        "Limitetotaldecrédito" => :credit_limit,
        "Limitedisponível" => :available_limit
      }.freeze
      # Labels whose value can appear several times on a bill, once per card, and add up.
      SUMMED = %i[purchases].freeze

      def initialize(pdftotext: "pdftotext")
        @pdftotext = pdftotext
      end

      def call(_file_name, content)
        pages = words(content)
        raise Error, "the PDF has no text pages" if pages.size < 2

        figures = {}
        dates = summary_dates(pages.first, figures)
        state = {section: nil, cardholder: nil, expect_cardholder: false, last: nil}
        entries = []

        pages.drop(1).each do |page|
          columns(page).each do |column|
            lines(column).each { |line| read_line(line, state, entries, figures) }
            state[:last] = nil
          end
        end

        build(entries, figures, dates)
      end

      private

      # --- Reading the PDF ------------------------------------------------------------

      def words(content)
        Tempfile.create(["itau", ".pdf"], binmode: true) do |file|
          file.write(content)
          file.flush
          output, error, status = Open3.capture3(@pdftotext, "-bbox", file.path, "-")
          raise Error, "pdftotext could not read the PDF: #{error.strip}" unless status.success?

          parse_bbox(output.force_encoding(Encoding::UTF_8))
        end
      rescue Errno::ENOENT
        raise Error, "pdftotext is not installed (Debian/Raspberry Pi OS: apt install poppler-utils)"
      end

      def parse_bbox(html)
        pages = []
        html.each_line do |line|
          if line.include?("<page ")
            pages << []
          elsif (m = /<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">(.*)<\/word>/.match(line))
            pages.last << Word.new(m[1].to_f, m[2].to_f, m[3].to_f, m[4].to_f, CGI.unescapeHTML(m[5]))
          end
        end
        pages.map { rejoin(_1) }
      end

      # Glues word fragments that poppler split apart (see JOIN_GAP).
      def rejoin(words)
        rows = words.group_by { _1.y_min.round(1) }.values.map { |row| row.sort_by(&:x_min) }
        gaps = rows.flat_map { |row| row.each_cons(2).map { |a, b| b.x_min - a.x_max } }.select { (0...4).cover?(_1) }
        fragmented = gaps.any? && gaps.count { _1 < FRAGMENT_GAP } > gaps.size * FRAGMENTED_SHARE
        join_gap = fragmented ? JOIN_GAP : TOUCHING_GAP

        rows.flat_map do |row|
          row.each_with_object([]) do |word, out|
            previous = out.last
            gap = previous && word.x_min - previous.x_max
            if gap && gap >= -0.01 && gap < join_gap
              previous.text += word.text
              previous.x_max = word.x_max
            else
              out << word.dup
            end
          end
        end
      end

      # Splits a page at its "DATA ... VALOR EM R$" column headers. A column runs from its
      # "DATA" to just past its "R$", so text beside the last column (limits, interest
      # rates) stays out of it. Pages without a header have no columns.
      def columns(words)
        headers = words.select { _1.text == "DATA" }.sort_by(&:x_min)
          .each_with_object([]) { |word, list| list << word if list.empty? || word.x_min - list.last.x_min > 40 }

        headers.each_with_index.map do |data, index|
          next_left = headers[index + 1] ? headers[index + 1].x_min - 5 : Float::INFINITY
          currency = words.select { _1.text == "R$" && _1.x_min > data.x_max && (_1.y_min - data.y_min).abs < LINE_TOLERANCE }
            .min_by(&:x_min)
          right = [currency ? currency.x_max + 10 : Float::INFINITY, next_left].min
          words.select { _1.x_min >= data.x_min - 12 && _1.x_min < right }
        end
      end

      # Groups words into lines, top to bottom, each line left to right.
      def lines(words)
        words.sort_by { [_1.y_min, _1.x_min] }
          .slice_when { |a, b| b.y_min - a.y_min > LINE_TOLERANCE }
          .map { |line| merge_numbers(line.sort_by(&:x_min)) }
      end

      # "12.929" ",61" a little apart is still one amount.
      def merge_numbers(words)
        words.each_with_object([]) do |word, out|
          previous = out.last
          if previous && word.x_min - previous.x_max < 2.5 &&
              word.text.match?(/\A[-\d.,]+\z/) && previous.text.match?(/\A-?[\d.,]+\z/)
            previous.text += word.text
            previous.x_max = word.x_max
          else
            out << word.dup
          end
        end.map(&:text)
      end

      # --- Interpreting the lines -----------------------------------------------------

      def summary_dates(words, figures)
        dates = {}
        lines(words).each do |tokens|
          joined = tokens.join(" ")
          compact = tokens.join
          dates[:due_on] ||= full_date(compact, "Vencimento:")
          dates[:closing_on] ||= full_date(compact, "Postagem:") || full_date(compact, "Emissão:")
          collect_figures(tokens, figures, page_one: true) unless joined.empty?
        end
        dates
      end

      def full_date(compact, label)
        index = compact.index(label) or return nil
        match = FULL_DATE.match(compact, index) or return nil
        Date.new(match[3].to_i, match[2].to_i, match[1].to_i)
      rescue Date::Error
        nil
      end

      def read_line(tokens, state, entries, figures)
        compact = tokens.join.delete_prefix("P").delete_prefix("L")
        heading = SECTIONS.find { |label, _| tokens.join.start_with?(label) || compact.start_with?(label) }
        if heading
          state[:section] = heading.last
          state[:expect_cardholder] = heading.last == :purchases
          state[:last] = nil
          return
        end

        if tokens.first == "DATA"
          state[:expect_cardholder] = false
          return
        end

        collect_figures(tokens, figures)

        if tokens.size >= 3 && DAY_MONTH.match?(tokens.first) && AMOUNT.match?(tokens.last)
          state[:expect_cardholder] = false
          entry = {section: state[:section], date: tokens.first, description: tokens[1..-2].join(" "),
                   amount: tokens.last, cardholder: state[:cardholder]}
          entries << entry
          state[:last] = entry
        elsif tokens.join.length < 3
          # A lone marker letter ("L", "P") printed beside a total, a little off its line.
          nil
        elsif state[:last] && !AMOUNT.match?(tokens.last) && !DAY_MONTH.match?(tokens.first)
          # The line under a transaction: "<bank category> <city>", or a fee's detail.
          state[:last][:detail] = tokens.join(" ")
          state[:last] = nil
        elsif state[:expect_cardholder] && tokens.none? { AMOUNT.match?(_1) }
          state[:cardholder] = tokens.join(" ")
          state[:expect_cardholder] = false
        else
          state[:last] = nil
        end
      end

      def collect_figures(tokens, figures, page_one: false)
        amount = tokens.reverse.find { AMOUNT.match?(_1) } or return
        compact = tokens.join
        LABELS.each do |label, key|
          next unless compact.include?(label)
          # On page 1 the summary shares lines with the address block, so the label has to
          # come right before its amount.
          next if page_one && !compact.match?(/#{Regexp.escape(label)}[^,]*#{Regexp.escape(amount)}\z/)
          next if label == "Lançamentosatuais" && compact.include?("Totaldoslançamentosatuais")

          cents = Money.parse(amount).cents
          if SUMMED.include?(key)
            figures[key] = figures.fetch(key, 0) + cents
          else
            figures[key] ||= cents
          end
          break
        end
      end

      # --- Building the statement -----------------------------------------------------

      def build(entries, figures, dates)
        due_on = dates[:due_on] or raise Error, "due date (Vencimento) not found on page 1"
        closing_on = dates[:closing_on] or raise Error, "closing date (Postagem) not found on page 1"

        current = entries.select { %i[payments purchases fees].include?(_1[:section]) }
        future = entries.select { _1[:section] == :future }
        cents = ->(section) { current.select { _1[:section] == section }.sum { Money.parse(_1[:amount]).cents } }

        purchases = cents.(:purchases)
        fees = cents.(:fees)
        payments = cents.(:payments)
        check!(figures, :purchases, purchases, "purchases (Lançamentos no cartão)")
        check!(figures, :fees, fees, "fees (Lançamentos produtos e serviços)", optional: true)
        check!(figures, :current, purchases + fees, "this bill's charges (Lançamentos atuais)")
        check!(figures, :payments, payments, "payments (Total dos pagamentos)", optional: true)
        raise Error, "this bill's total (Total desta fatura) not found" unless figures[:total]

        warnings = []
        future_cents = future.sum { Money.parse(_1[:amount]).cents }
        if figures[:next_statement] && future_cents != figures[:next_statement]
          warnings << "the future installments list adds up to #{Money.new(future_cents)}, " \
            "not the printed next bill (#{Money.new(figures[:next_statement])}); kept the printed figure"
        end

        repeats = Repeats.new
        rows = current.map { row(_1, due_on, closing_on, repeats) }
        dates = rows.flat_map { [_1.occurred_on, _1.purchased_on] }.compact

        Statement.new(
          source: SOURCE, account_name: ACCOUNT,
          period_start: dates.min || closing_on, period_end: [dates.max, closing_on].compact.max,
          rows:, warnings:,
          card_statement: {
            due_on:, closing_on:,
            total_cents: figures[:total],
            previous_total_cents: figures[:previous_total],
            payments_cents: -payments,
            purchases_cents: purchases,
            fees_cents: fees,
            next_statement_cents: figures[:next_statement],
            later_statements_cents: figures[:later_statements],
            credit_limit_cents: figures[:credit_limit],
            available_limit_cents: figures[:available_limit]
          }
        )
      end

      def check!(figures, key, parsed, name, optional: false)
        printed = figures[key]
        if printed.nil?
          return if optional && parsed.zero?

          raise Error, "the printed total for #{name} was not found, so the rows can't be checked"
        end
        return if printed == parsed

        raise Error, "#{name}: the rows add up to #{Money.new(parsed)}, but the bill prints #{Money.new(printed)}"
      end

      def row(entry, due_on, closing_on, repeats)
        day, month = DAY_MONTH.match(entry[:date]).captures.map(&:to_i)
        # No year on the rows: a month after the closing month belongs to the year before.
        year = month > closing_on.month ? closing_on.year - 1 : closing_on.year
        date = begin
          Date.new(year, month, day)
        rescue Date::Error
          raise Error, "not a date: #{entry[:date]} (#{entry[:description]})"
        end

        printed = Money.parse(entry[:amount])
        raise Error, "zero amount: #{entry[:description]}" if printed.zero?

        amount = -printed
        raw_description = entry[:description]
        k = repeats.next(date, raw_description, printed.cents)
        external_id = Importers.digest(SOURCE, due_on, date, raw_description, printed.cents, k)
        raw = {"section" => entry[:section].to_s, "date" => entry[:date], "description" => raw_description,
               "amount" => entry[:amount], "detail" => entry[:detail], "cardholder" => entry[:cardholder]}.compact

        if entry[:section] == :payments
          return Row.new(external_id:, occurred_on: date, amount:, kind: "transfer",
            description: raw_description, raw_description:, counter_account: "Itaú conta", raw:)
        end

        name = raw_description
        number = total = nil
        if (match = INSTALLMENT.match(name))
          number, total = match[1].to_i, match[2].to_i
          name = match.pre_match.strip
        end

        bank_category, location = nil
        if entry[:section] == :purchases && entry[:detail]
          bank_category, location = entry[:detail].split(" ", 2)
          bank_category = bank_category.downcase
        end
        name = strip_city(name, location)

        # The card fee and its discount ("Redução Mensalidade", negative) are both fees.
        kind = if entry[:section] == :fees then "fee"
        elsif amount.positive? then "refund"
        else "purchase"
        end

        Row.new(
          external_id:,
          # Installments count in the month of the bill that charges them (section 5).
          occurred_on: total ? closing_on : date,
          purchased_on: total ? date : nil,
          amount:, kind:,
          description: name,
          raw_description:,
          bank_category:, location:,
          installment_number: number, installment_total: total,
          purchase_key: total && Importers.digest(SOURCE, name, date, printed.cents, total),
          counterparty: (kind == "fee") ? nil : {name:},
          raw:
        )
      end

      # Merchant names are cut at about 23 characters with the city glued on
      # ("PADARIA EXEMPLOSAO PAULO", "LOJA EXEMPLOCAMPINASBR"). Drops the longest start of
      # the row's city found at the end of the name, plus a trailing "B"/"BR".
      def strip_city(name, location)
        return name if location.nil? || location.length < 3

        location.length.downto(3) do |size|
          prefix = Regexp.escape(location[0, size])
          match = /#{prefix}(?:BR?)?\z/i.match(name) or next
          rest = match.pre_match.strip
          return rest if rest.length >= 3
        end
        name
      end
    end
  end
end
