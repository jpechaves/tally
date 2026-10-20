# frozen_string_literal: true

module Tally
  module Importers
    class ItauCardPdf
      # Reads the bill's lines in order: page 1's dates and summary, then each column of
      # the transaction pages. Collects the entries (one per transaction, as printed) and
      # the printed figures (cents, by LABELS key).
      class Reader
        # Section headings, compared with spaces removed (fragments make spacing unreliable).
        SECTIONS = {
          "Pagamentosefetuados" => :payments,
          "Lançamentos:comprasesaques" => :purchases,
          "Lançamentos:produtoseserviços" => :fees,
          "Lançamentosinternacionais" => :international,
          "Comprasparceladas" => :future,
          "Limitesdecrédito" => :other,
          "Encargoscobradosnestafatura" => :other,
          "Novotetodejuros" => :other,
          "Simulação" => :other,
          "Fiqueatento" => :other
        }.freeze
        # Sections whose rows start with the cardholder's name.
        CARDHOLDER_SECTIONS = %i[purchases international].freeze

        # Printed figures, by label (spaces removed). The value is the last amount on the line.
        LABELS = {
          "Totaldafaturaanterior" => :previous_total,
          "Totaldestafatura" => :total,
          "Lançamentosatuais" => :current,
          "Totaldoslançamentosatuais" => :current,
          "Totaldospagamentos" => :payments,
          "Lançamentosnocartão" => :purchases,
          "Lançamentosprodutoseserviços" => :fees,
          "Totallançamentosinter.emR$" => :international,
          "Saldofinanciado" => :financed,
          "Próximafatura" => :next_statement,
          "Demaisfaturas" => :later_statements,
          "Limitetotaldecrédito" => :credit_limit,
          "Limitedisponível" => :available_limit
        }.freeze
        # Labels whose value can appear several times on a bill, once per card, and add up.
        SUMMED = %i[purchases international].freeze
        # The IOF tax on international purchases, printed under them without a date.
        IOF = "RepassedeIOF"

        attr_reader :entries, :figures

        def initialize
          @entries = []
          @figures = {}
          @section = @cardholder = @last = nil
          @expect_cardholder = false
        end

        # Page 1: the due and closing dates, and the summary's figures.
        #
        # @param lines [Array<Array<String>>]
        # @return [Hash] :due_on and :closing_on, when printed
        def summary(lines)
          dates = {}
          lines.each do |tokens|
            compact = tokens.join
            dates[:due_on] ||= full_date(compact, "Vencimento:")
            dates[:closing_on] ||= full_date(compact, "Postagem:") || full_date(compact, "Emissão:")
            # The summary shares lines with the address block, so the label has to come
            # right before its amount.
            collect_figures(tokens) { |label, amount| compact.match?(/#{Regexp.escape(label)}[^,]*#{Regexp.escape(amount)}\z/) }
          end
          dates
        end

        # One column of a transaction page, top to bottom.
        def column(lines)
          lines.each { read_line(_1) }
          @last = nil
        end

        private

        def full_date(compact, label)
          index = compact.index(label) or return nil
          match = FULL_DATE.match(compact, index) or return nil
          Date.new(match[3].to_i, match[2].to_i, match[1].to_i)
        rescue Date::Error
          nil
        end

        def read_line(tokens)
          text = tokens.join
          if (section = section(text))
            start_section(section)
          elsif tokens.first == "DATA"
            @expect_cardholder = false
          else
            collect_figures(tokens)
            read_row(tokens, text)
          end
        end

        def section(text)
          compact = text.delete_prefix("P").delete_prefix("L")
          SECTIONS.each { |label, section| return section if text.start_with?(label) || compact.start_with?(label) }
          nil
        end

        def start_section(section)
          @section = section
          @expect_cardholder = CARDHOLDER_SECTIONS.include?(section)
          @last = nil
        end

        def read_row(tokens, text)
          first, last = tokens.first, tokens.last

          if @section == :international && text.start_with?(IOF) && AMOUNT.match?(last)
            add_entry(section: :iof, date: nil, description: "Repasse de IOF", amount: last)
            @last = nil
          elsif tokens.size >= 3 && DAY_MONTH.match?(first) && AMOUNT.match?(last)
            @expect_cardholder = false
            @last = add_entry(section: @section, date: first, description: tokens[1..-2].join(" "), amount: last)
          elsif text.length < 3
            # A lone marker letter ("L", "P") printed beside a total, a little off its line.
            nil
          elsif @last && !AMOUNT.match?(last) && !DAY_MONTH.match?(first)
            # The line under a transaction: "<bank category> <city>", or a fee's detail.
            @last[:detail] = tokens.join(" ")
            @last = nil
          elsif @expect_cardholder && tokens.none? { AMOUNT.match?(_1) }
            @cardholder = tokens.join(" ")
            @expect_cardholder = false
          else
            @last = nil
          end
        end

        def add_entry(**entry)
          entry[:cardholder] = @cardholder
          @entries << entry
          entry
        end

        # Records the line's figure, if it has a label and an amount. A block, when given,
        # says whether the label goes with the amount.
        def collect_figures(tokens)
          amount = tokens.reverse.find { AMOUNT.match?(_1) } or return
          compact = tokens.join
          LABELS.each do |label, key|
            next unless compact.include?(label)
            next if block_given? && !yield(label, amount)
            # simplecov:disable branch — the case differs ("lançamentos"), so this label never matches that line
            next if label == "Lançamentosatuais" && compact.include?("Totaldoslançamentosatuais")
            # simplecov:enable branch

            return record(key, Money.parse(amount).cents)
          end
        end

        def record(key, cents)
          if SUMMED.include?(key)
            @figures[key] = @figures.fetch(key, 0) + cents
          else
            @figures[key] ||= cents
          end
        end
      end
    end
  end
end
