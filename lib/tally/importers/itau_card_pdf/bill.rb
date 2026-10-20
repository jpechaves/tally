# frozen_string_literal: true

module Tally
  module Importers
    class ItauCardPdf
      # Turns the entries and figures a {Reader} collected into the {Statement}, after
      # checking the entries against the printed totals.
      class Bill
        # The sections charged on this bill (the future installments are not).
        CURRENT = %i[payments purchases international iof fees].freeze
        # Totals a bill only prints when it has rows of that kind.
        OPTIONAL = %i[international fees payments].freeze
        # A run of at least this many rows printed again further down is a reprint
        # (see #drop_reprint).
        REPRINT_MIN = 3

        # @param dates [Hash] :due_on and :closing_on
        def initialize(entries, figures, dates)
          @figures = figures
          @due_on = dates[:due_on] or raise Error.new(:due_date_missing)
          @closing_on = dates[:closing_on] or raise Error.new(:closing_date_missing)
          @current = entries.select { CURRENT.include?(_1[:section]) }
          @reprinted = drop_reprint(@current)
          @sums = sums(@current)
          @future = sums(entries)[:future]
        end

        def statement
          check_totals
          warnings = [reprint_warning, future_warning].compact
          repeats = Repeats.new
          rows = @current.map { row(_1, repeats) }
          dates = rows.flat_map { [_1.occurred_on, _1.purchased_on] }.compact

          Statement.new(
            source: SOURCE, account_name: ACCOUNT,
            period_start: dates.min || @closing_on, period_end: [dates.max, @closing_on].compact.max,
            rows:, warnings:, card_statement:
          )
        end

        private

        # @return [Hash] cents by section, 0 for a section with no entries
        def sums(entries)
          Hash.new(0).merge(entries.group_by { _1[:section] }.transform_values { |group| group.sum { Money.parse(_1[:amount]).cents } })
        end

        def check_totals
          purchases, international, fees = @sums.values_at(:purchases, :international, :fees)
          international += @sums[:iof]
          {
            purchases:, international:, fees:, current: purchases + international + fees, payments: @sums[:payments]
          }.each do |key, parsed|
            next if OPTIONAL.include?(key) && @figures[key].nil? && parsed.zero?

            verify(key, parsed)
          end
          raise Error.new(:total_missing) unless @figures[:total]
        end

        # `key` is also the section's name in importer.sections (config/i18n); `values` go
        # into it.
        def verify(key, parsed, **values)
          printed = @figures[key] or raise Error.new(:section_total_missing, section: key, **values)
          return if printed == parsed

          raise Error.new(:section_mismatch, section: key, sum_cents: parsed, printed_cents: printed, **values)
        end

        def reprint_warning
          return if @reprinted.empty?

          reprint = @sums[:reprinted]
          rows = @reprinted.size
          financed = @figures[:financed] or raise Error.new(:financed_missing)
          verify(:total, financed + @figures[:current] + reprint, rows:)
          Notice[:reprinted, rows:, amount_cents: reprint]
        end

        def future_warning
          printed = @figures[:next_statement]
          return unless printed && printed != @future

          Notice[:future_installments, sum_cents: @future, printed_cents: printed]
        end

        def card_statement
          {
            due_on: @due_on, closing_on: @closing_on,
            total_cents: @figures[:total],
            previous_total_cents: @figures[:previous_total],
            payments_cents: -@sums[:payments],
            purchases_cents: @sums[:purchases] + @sums[:international],
            fees_cents: @sums[:fees] + @sums[:iof],
            next_statement_cents: @figures[:next_statement],
            later_statements_cents: @figures[:later_statements],
            credit_limit_cents: @figures[:credit_limit],
            available_limit_cents: @figures[:available_limit]
          }
        end

        # Some bills print a block of rows twice, word for word: once at the top of the
        # purchases and again just before their total. Neither copy counts in "Lançamentos no
        # cartão" or "Lançamentos atuais", but "Total desta fatura" counts the block once. Drops
        # the second copy from `entries`, moves the first to its own section and returns it.
        def drop_reprint(entries)
          purchases = entries.select { _1[:section] == :purchases }
          reprint = find_reprint(purchases.map { _1.values_at(:date, :description, :amount) }) or return []
          first, second, length = reprint

          copy = Set.new(purchases[second, length]).compare_by_identity
          entries.reject! { copy.include?(_1) }
          purchases[first, length].each { _1[:section] = :reprinted }
        end

        # @return [Array(Integer, Integer, Integer), nil] where the first run of keys printed
        #   again starts, where its copy starts, and its length
        def find_reprint(keys)
          keys.each_index do |first|
            (first + 1...keys.size).each do |second|
              length = run_length(keys, first, second)
              return [first, second, length] if length >= REPRINT_MIN
            end
          end
          nil
        end

        def run_length(keys, first, second)
          length = 0
          length += 1 while first + length < second && second + length < keys.size &&
              keys[first + length] == keys[second + length]
          length
        end

        def row(entry, repeats)
          # The IOF line has no date; it is charged on this bill.
          date = entry[:date] ? row_date(entry) : @closing_on
          printed = Money.parse(entry[:amount])
          raw_description = entry[:description]
          raise Error.new(:entry_zero_amount, text: raw_description) if printed.zero?

          cents = printed.cents
          k = repeats.next(date, raw_description, cents)
          common = {
            external_id: Importers.digest(SOURCE, @due_on, date, raw_description, cents, k),
            amount: -printed, raw_description:, raw: raw(entry)
          }

          if entry[:section] == :payments
            Row.new(**common, occurred_on: date, kind: "transfer", description: raw_description, counter_account: "Itaú conta")
          else
            Row.new(**common, **charge(entry, date, printed))
          end
        end

        def raw(entry)
          {"section" => entry[:section].to_s, "date" => entry[:date], "description" => entry[:description],
           "amount" => entry[:amount], "detail" => entry[:detail], "cardholder" => entry[:cardholder]}.compact
        end

        # A purchase, refund or fee's fields.
        def charge(entry, date, printed)
          section = entry[:section]
          name, number, total = installment(entry[:description])
          bank_category, location = detail(entry)
          name = strip_city(name, location)
          # The card fee and its discount ("Redução Mensalidade", negative) are both fees, and
          # so is the IOF on international purchases.
          kind = if %i[fees iof].include?(section) then "fee"
          elsif printed.negative? then "refund"
          else "purchase"
          end

          {
            # Installments count in the month of the bill that charges them (section 5).
            occurred_on: total ? @closing_on : date,
            purchased_on: total ? date : nil,
            kind:, description: name, bank_category:, location:,
            installment_number: number, installment_total: total,
            purchase_key: total && Importers.digest(SOURCE, name, date, printed.cents, total),
            counterparty: (kind == "fee") ? nil : {name:}
          }
        end

        # @return [Array(String, Integer, Integer)] the name without "08/10", and the
        #   installment's number and total, if it is one
        def installment(description)
          match = INSTALLMENT.match(description) or return [description, nil, nil]
          [match.pre_match.strip, match[1].to_i, match[2].to_i]
        end

        # @return [Array(String, String)] the bank's category and the city, from the line
        #   under a purchase
        def detail(entry)
          detail = entry[:detail]
          return [] unless detail && %i[purchases reprinted].include?(entry[:section])

          bank_category, location = detail.split(" ", 2)
          [bank_category.downcase, location]
        end

        def row_date(entry)
          day, month = DAY_MONTH.match(entry[:date]).captures.map(&:to_i)
          # No year on the rows: a month after the closing month belongs to the year before.
          year = (month > @closing_on.month) ? @closing_on.year - 1 : @closing_on.year
          Date.new(year, month, day)
        rescue Date::Error
          raise Error.new(:entry_not_a_date, date: entry[:date], text: entry[:description])
        end

        # Merchant names are cut at about 23 characters with the city glued on
        # ("PADARIA EXEMPLOSAO PAULO", "LOJA EXEMPLOCAMPINASBR"). Drops the longest start of
        # the row's city found at the end of the name, plus a trailing "B"/"BR".
        def strip_city(name, location)
          return name if location.to_s.length < 3

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
end
