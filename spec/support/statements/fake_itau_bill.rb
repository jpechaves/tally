# frozen_string_literal: true

require "bigdecimal"

# Builds synthetic Itaú credit card bills (PDF) for the golden-file tests.
#
# The repository is public, so no real bill can be a fixture (docs/architecture.md,
# section 17). These copy the real layout and its quirks with made-up people, merchants
# and amounts:
#
# - page 1: the summary (previous bill, payment, this bill's total, closing and due dates)
#   beside an address block, so labels share lines with unrelated text
# - next pages: two or three columns per page at different x positions, each starting
#   with a "DATA ... VALOR EM R$" header, rows with the bank's category and city on the
#   line below, installments ("NN/MM"), refunds, the card fee and its discount, and the
#   future installments list
# - words 1.2 pt apart (a real bill's spacing), or, with `tight: true`, every word split
#   into fragments 0.9 pt apart, the way poppler reads bills drawn with tight letter
#   spacing ("DAT A", "1.234 ,56")
# - optionally, international purchases (with the original amount on the line below and
#   the IOF tax without a date), and a block of rows printed twice: at the top of the
#   purchases and again before their total, left out of the purchases and the current
#   charges but counted once in the bill's total
#
# Run `bundle exec ruby spec/support/statements/build_fixtures.rb` to rewrite the fixture
# files after changing a bill here.
class FakeItauBill
  FONT_SIZE = 7.0
  CHAR_WIDTH = FONT_SIZE * 0.6 # Courier: every glyph is 600/1000 em
  WORD_GAP = 1.2
  TIGHT_WORD_GAP = 1.8
  FRAGMENT_GAP = 0.9
  LINE = 10.0
  PAGE_HEIGHT = 842

  Row = Struct.new(:date, :description, :amount, :detail)

  # @param closing [String] "DD/MM/YYYY", printed as Postagem
  # @param due [String] "DD/MM/YYYY", printed as Vencimento
  # @param payments [Array<Row>] the previous bill's payment(s), negative amounts
  # @param purchases [Array<Row>] amounts as printed: charges positive, refunds negative
  # @param fees [Array<Row>]
  # @param international [Array<Row>] amounts in R$; the detail is the original amount
  # @param iof [String, nil] "Repasse de IOF em R$"
  # @param reprinted [Array<Row>] the block printed twice (see above)
  # @param future [Array<Row>] next bill's installments (not this bill's transactions)
  # @param later [String] "Demais faturas"
  # @param layout [Array<Array<Integer>>] for each transaction page, the x of each column
  # @param split [Array<Integer>] how many purchase rows go in each column before the
  #   totals; the rest go in the last column that holds purchases
  def initialize(closing:, due:, previous_total:, payments:, purchases:, fees:, future:, later:,
    cardholder:, credit_limit:, available_limit:, layout:, split:, tight: false, international: [], iof: nil,
    reprinted: [])
    @closing, @due = closing, due
    @international, @iof, @reprinted = international, iof, reprinted
    @previous_total = previous_total
    @payments, @purchases, @fees, @future = payments, purchases, fees, future
    @later, @cardholder = later, cardholder
    @credit_limit, @available_limit = credit_limit, available_limit
    @layout, @split, @tight = layout, split, tight
  end

  def purchases_total = sum(@purchases)

  def fees_total = sum(@fees)

  def international_total = sum(@international) + (@iof ? cents(@iof) : 0)

  def current = purchases_total + international_total + fees_total

  def total = current + sum(@reprinted)

  # Page 1, then the transaction pages; tests can move or drop their words before
  # rendering them with PDFWriter.
  def pages = [summary_page] + transaction_pages

  def to_pdf = PDFWriter.new(pages).render

  private

  def sum(rows) = rows.sum { cents(_1.amount) }

  # The payment was made in the month before closing, so in December for a January bill.
  def payment_year
    month = @payments.first.date[3, 2].to_i
    year = @closing[6, 4].to_i
    (month > @closing[3, 2].to_i) ? year - 1 : year
  end

  def cents(text) = (BigDecimal(text.delete(".").tr(",", ".")) * 100).to_i

  def money(cents)
    units, rest = cents.abs.divmod(100)
    grouped = units.to_s.reverse.scan(/\d{1,3}/).join(".").reverse
    "#{"-" if cents.negative?}#{grouped},#{rest.to_s.rjust(2, "0")}"
  end

  # --- Page 1 -------------------------------------------------------------------------

  def summary_page
    page = Page.new(tight: @tight)
    page.text(400, 60, "Resumo da fatura em R$", bold: true)

    address = [@cardholder, "RUA DAS PALMEIRAS, 100", "BAIRRO EXEMPLO", "01234-567 CIDADE EXEMPLO SP"]
    summary = [
      ["Total da fatura anterior", money(cents(@previous_total))],
      ["Pagamento efetuado em #{@payments.first.date}/#{payment_year}", money(sum(@payments))],
      ["S Saldo financiado", "0,00"],
      ["L Lançamentos atuais", money(current)]
    ]
    address.each_with_index { |line, i| page.text(90, 80 + i * LINE, line) }
    summary.each_with_index do |(label, value), i|
      page.text(350, 80 + i * LINE, label)
      page.right(560, 80 + i * LINE, value)
    end

    page.text(200, 130, "Postagem: #{@closing}")
    page.text(200, 130 + LINE, "Vencimento: #{@due}")
    page.text(350, 130 + LINE, "= Total desta fatura", bold: true)
    page.right(560, 130 + LINE, money(total), bold: true)
    page.text(200, 130 + 2 * LINE, "Emissão: #{@closing}")

    page.text(50, 200, "O total da sua fatura é:")
    page.text(250, 200, "Com vencimento em:")
    page.text(420, 200, "Limite total de crédito:")
    page.text(50, 200 + LINE, "R$ #{money(total)}", bold: true)
    page.text(250, 200 + LINE, @due)
    page.text(420, 200 + LINE, "R$ #{money(cents(@credit_limit))}")
    page.text(50, 260, "Pagamento mínimo: R$ #{money(total / 20)}")
    page
  end

  # --- Transaction pages ----------------------------------------------------------------

  # Lays out the sections in reading order: down each column, then the next column, then
  # the next page, the way the bank does.
  def transaction_pages
    blocks = []
    blocks << [:heading, "Pagamentos efetuados"] << [:header]
    @payments.each { blocks << [:row, _1] }
    blocks << [:total, "P Total dos pagamentos", money(sum(@payments))] << [:gap]
    blocks << [:heading, "Lançamentos: compras e saques"] << [:text, @cardholder] << [:header]

    remaining = @reprinted + @purchases + @reprinted
    columns = @layout.flatten.size
    column_blocks = Array.new(columns) { [] }
    column_blocks[0] = blocks

    @split.each_with_index do |count, index|
      column = column_blocks[index]
      if index.positive?
        column << [:heading, "Lançamentos: compras e saques"] << [:header]
      end
      remaining.shift(count).each { column << [:row, _1] }
    end

    last = column_blocks[@split.size - 1]
    remaining.each { last << [:row, _1] }
    last << [:total, "Lançamentos no cartão", money(purchases_total)] << [:gap]
    if @international.any?
      last << [:heading, "Lançamentos internacionais"] << [:text, @cardholder] << [:header, "ESTABELECIMENTO US$"]
      @international.each { last << [:row, _1] }
      last << [:total, "Total transações inter. em R$", money(sum(@international))]
      last << [:total, "Repasse de IOF em R$", @iof] if @iof
      last << [:total, "Total lançamentos inter. em R$", money(international_total)] << [:gap]
    end
    last << [:heading, "Lançamentos: produtos e serviços"] << [:header, "PRODUTOS/SERVIÇOS"]
    @fees.each { last << [:row, _1] }
    last << [:total, "Lançamentos produtos e serviços", money(fees_total)]
    last << [:total, "L Total dos lançamentos atuais", money(current)] << [:gap]

    future = column_blocks[@split.size]
    future << [:heading, "Compras parceladas - próximas faturas"] << [:header]
    @future.each { future << [:row, _1.to_h.merge(detail: nil).then { |h| Row.new(**h) }] }
    future << [:total, "Próxima fatura", money(sum(@future))]
    future << [:total, "Demais faturas", money(cents(@later))]
    future << [:total, "Total para próximas faturas", money(sum(@future) + cents(@later))] << [:gap]
    future << [:heading, "Limites de crédito"]
    future << [:total, "Limite total de crédito", money(cents(@credit_limit))]
    future << [:total, "Limite disponível", money(cents(@available_limit))]

    index = 0
    @layout.map do |xs|
      page = Page.new(tight: @tight)
      xs.each do |x|
        draw_column(page, x, column_blocks[index])
        index += 1
      end
      page.text(500, 800, "continua...") unless index == columns
      page
    end
  end

  def draw_column(page, x, blocks)
    width = 175
    y = 60
    blocks.each do |kind, *args|
      case kind
      when :heading
        page.text(x, y, args[0], bold: true)
      when :header
        page.text(x, y, "DATA", bold: true)
        page.text(x + 30, y, args[0] || "ESTABELECIMENTO", bold: true)
        page.right(x + width, y, "VALOR EM R$", bold: true)
      when :text
        page.text(x, y, args[0])
      when :row
        row = args[0]
        page.text(x, y, row.date)
        page.text(x + 30, y, row.description)
        page.right(x + width, y, row.amount)
        if row.detail
          y += LINE
          page.text(x + 30, y, row.detail)
        end
      when :total
        page.text(x, y, args[0], bold: true)
        page.right(x + width, y, args[1], bold: true)
      when :gap
        nil
      end
      y += LINE
    end
  end

  # One page's text, drawn word by word so the spacing is exact.
  class Page
    attr_reader :items

    def initialize(tight:)
      @tight = tight
      @items = []
    end

    def text(x, y, string, bold: false)
      cursor = x.to_f
      string.split(" ").each do |word|
        fragments(word).each_with_index do |fragment, index|
          cursor += FRAGMENT_GAP if index.positive?
          @items << [cursor, y, fragment, bold]
          cursor += fragment.length * CHAR_WIDTH
        end
        cursor += @tight ? TIGHT_WORD_GAP : WORD_GAP
      end
    end

    def right(x_right, y, string, bold: false)
      text(x_right - width(string), y, string, bold:)
    end

    private

    def width(string)
      words = string.split(" ")
      gaps = words.sum { fragments(_1).size - 1 } * FRAGMENT_GAP
      words.sum(&:length) * CHAR_WIDTH + gaps + (words.size - 1) * (@tight ? TIGHT_WORD_GAP : WORD_GAP)
    end

    # In a tight bill, words longer than 3 letters break into pieces of 2-3 letters.
    def fragments(word)
      return [word] if !@tight || word.length <= 3

      word.scan(/.{1,3}/)
    end
  end

  # The smallest PDF that poppler reads: standard Courier fonts (no embedding), WinAnsi
  # text, one content stream per page. Deterministic: same input, same bytes.
  class PDFWriter
    def initialize(pages)
      @pages = pages
    end

    def render
      objects = []
      objects << "<< /Type /Catalog /Pages 2 0 R >>"
      kids = @pages.each_index.map { |i| "#{5 + i * 2} 0 R" }.join(" ")
      objects << "<< /Type /Pages /Kids [#{kids}] /Count #{@pages.size} >>"
      objects << "<< /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding >>"
      objects << "<< /Type /Font /Subtype /Type1 /BaseFont /Courier-Bold /Encoding /WinAnsiEncoding >>"
      @pages.each_with_index do |page, i|
        objects << "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 #{PAGE_HEIGHT}] " \
          "/Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents #{6 + i * 2} 0 R >>"
        stream = content(page)
        objects << "<< /Length #{stream.bytesize} >>\nstream\n#{stream}\nendstream"
      end

      out = "%PDF-1.4\n%\xE2\xE3\xCF\xD3\n".b
      offsets = objects.each_with_index.map do |object, i|
        offset = out.bytesize
        out << "#{i + 1} 0 obj\n".b << object.b << "\nendobj\n".b
        offset
      end
      xref = out.bytesize
      out << "xref\n0 #{objects.size + 1}\n0000000000 65535 f \n".b
      offsets.each { out << format("%010d 00000 n \n", _1).b }
      out << "trailer\n<< /Size #{objects.size + 1} /Root 1 0 R >>\nstartxref\n#{xref}\n%%EOF\n".b
    end

    private

    def content(page)
      ops = +"BT\n".b
      page.items.each do |x, y, text, bold|
        baseline = PAGE_HEIGHT - y - FONT_SIZE
        ops << "/#{bold ? "F2" : "F1"} #{FONT_SIZE} Tf 1 0 0 1 #{format("%.2f", x)} #{format("%.2f", baseline)} Tm (".b
        ops << escape(text.encode(Encoding::Windows_1252)) << ") Tj\n".b
      end
      ops << "ET".b
    end

    def escape(bytes)
      bytes.b.gsub(/[\\()]/n) { "\\#{_1}" }
    end
  end
end
