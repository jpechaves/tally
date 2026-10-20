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
      # Another currency shows its own symbol or code: "US$ 12,50", "GBP 41,20".
      def money(cents, currency = Tally::Money::DEFAULT_CURRENCY)
        cents.nil? ? "" : Tally::Money.new(cents, currency).format(locale)
      end

      # Amounts in several currencies, which never add up: "R$ 1.234,56 + US$ 45,10".
      # @param amounts [Hash] currency => cents
      def money_each(amounts)
        amounts.map { |currency, cents| money(cents, currency) }.join(" + ")
      end

      # A short amount for chart axes: "R$ 1,5 mil" ("R$ 1.5K" in English), "R$ 300"; another
      # currency with its own symbol or code: "US$ 300".
      def money_compact(cents, currency = Tally::Money::DEFAULT_CURRENCY)
        reais = cents.abs / 100.0
        text = if reais >= 1_000_000 then t("charts.millions", n: number(compact_round(reais / 1_000_000)))
        elsif reais >= 1_000 then t("charts.thousands", n: number(compact_round(reais / 1_000)))
        else number(reais.round)
        end
        "#{"-" if cents.negative?}#{Tally::Money::SYMBOLS.fetch(currency, currency)} #{text}"
      end

      # Columns over months or other labels (Tally::Charts.columns), amounts in cents.
      def columns_chart(currency: Tally::Money::DEFAULT_CURRENCY, **options)
        Tally::Charts.columns(format: ->(cents) { money(cents, currency) }, compact: ->(cents) { money_compact(cents, currency) },
          **options).html_safe
      end

      # 5.5949… reais per dollar -> "5,5949" ("5.5949" in English), for an exchange rate.
      def rate(value)
        number(BigDecimal(value, 12).round(4).to_s("F"))
      end

      # A horizontal bar's width, as a percentage of the largest one.
      def bar_percent(value, max) = Tally::Charts.percent(value, max)

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

      # A time the database keeps in UTC, in the TIME_ZONE setting:
      # "2026-09-02T22:08:12.123Z" -> "02/09/2026 19:08" in America/Sao_Paulo.
      def timestamp(text)
        return "" if text.to_s.empty?

        local = Hanami.app["settings"].time_zone.to_local(Time.iso8601(text.to_s))
        "#{l(local.to_date, format: :day)} #{local.strftime("%H:%M")}"
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

      def compact_round(value) = (value.round(1) == value.round) ? value.round : value.round(1)

      # A starting category's name in the current language; one you named yourself as typed.
      def category_name(name) = name && Tally::Categories.display(name, locale)

      # "Moradia › Energia", translated like category_name.
      def category_path(parent_name, name) = [parent_name, name].compact.map { category_name(_1) }.join(" › ")

      def category_label(row)
        return "" unless row[:category_name]

        name = category_name(row[:category_name])
        (row[:category_source] == "bank") ? "#{name}?" : name
      end

      # Your display name for a row's counterparty, when you gave it one (issue #37).
      def display_name(row)
        row[:counterparty_name] if row[:counterparty_bank_name] && row[:counterparty_name] != row[:counterparty_bank_name]
      end

      # " (you)" after a counterparty marked as you, " (Bruno)" after one marked as someone
      # else of the household (issue #21), nothing for anyone else.
      def person_label(party, people)
        return "" unless party[:is_self] == 1

        person = people.find { _1.id == party[:person_id] }
        (person == people.first) ? " #{t("counterparties.index.you")}" : " (#{person.name})"
      end

      # A link to the transactions behind a number (Tally::TransactionFilter), with the
      # way back to this page.
      def transactions_path(**filters) = with_back(Tally::TransactionFilter.new(**filters).path)

      # A link to a row's page, with the way back to this page; on that page itself, the
      # page as it is.
      def transaction_path(id)
        path = "/transactions/#{id}"
        (_context.request.path == path) ? here : with_back(path)
      end

      # This page, with its filters and page, for a link or form to come back to (issue #87).
      def here = _context.request.fullpath

      # +path+ with this page as the way back from it (?back=, Tally::Action#back_param).
      def with_back(path) = "#{path}#{path.include?("?") ? "&" : "?"}back=#{ERB::Util.url_encode(here)}"

      # The breadcrumb's crumb for the page a link came from, or +fallback+ ([label, path])
      # when it came from nowhere (shared/_breadcrumb).
      def parent_crumb(back, fallback, categories = []) = back ? [back_label(back, categories), back] : fallback

      # What the page at +back+ is called: its section ("Review"), a page below one
      # ("Transaction"), or the transactions with the filters that say which list it was:
      # "Transactions (Groceries, Sep 2026)". The filters' categories are named from
      # +categories+.
      def back_label(back, categories = [])
        path, query = back.split("?", 2)
        section, id = path.split("/").drop(1)
        return t("breadcrumb.detail.#{section}", default: t("breadcrumb.back")) if id
        return t("layout.nav.#{section || "home"}", default: t("breadcrumb.back")) unless section == "transactions"

        words = filter_words(query, categories)
        words.empty? ? t("layout.nav.transactions") : "#{t("layout.nav.transactions")} (#{words.join(", ")})"
      end

      # A transactions query's search, category and month, in words.
      def filter_words(query, categories)
        filter = Tally::TransactionFilter.parse(URI.decode_www_form(query.to_s).to_h { [_1.to_sym, _2] })
        category = if filter.category == Tally::TransactionFilter::NONE then t("transactions.index.uncategorized")
        else category_name(categories.find { _1[:id] == filter.category }&.[](:name))
        end
        [filter.q && "“#{filter.q}”", category, filter.month && month_label(filter.month)].compact
      end

      # A card purchase's installments still to pay from `month` on: "7 × R$ 120,00 = R$ 840,00".
      def installments_left(purchase, month)
        t("installments.left", count: purchase.left_from(month), each: money(purchase.cents), total: money(purchase.left_cents_from(month)))
      end

      # What a filter without a form field shows, for its badge on the transactions page.
      def carried_filter_label(key, value, payee:, purchase:, trip: nil)
        case key
        when :nature then nature_label((value == Tally::TransactionFilter::UNSET) ? nil : value)
        when :payee then payee
        when :purchase then purchase ? "#{purchase.description} (#{purchase.account_name})" : value
        when :trip then trip || value
        end
      end

      # An importer's error or warning in the reader's language (Importers::Notice); older
      # imports kept English text, shown as it is.
      def notice(value) = value.is_a?(Tally::Importers::Notice) ? value.text(locale) : value.to_s

      # A statement or bill missing between the imported ones (Tally::StatementGaps):
      # "falta o extrato de jun/2026" / "missing the Jun 2026 statement".
      def gap_label(gap)
        if gap.whole_months?
          from, to = [gap.from, gap.to].map { month_label(_1.strftime("%Y-%m")) }
          (from == to) ? t("gaps.#{gap.kind}.month", month: from) : t("gaps.#{gap.kind}.months", from:, to:)
        elsif gap.from == gap.to
          t("gaps.statement.day", day: date(gap.from.iso8601))
        else
          t("gaps.statement.days", from: date(gap.from.iso8601), to: date(gap.to.iso8601))
        end
      end

      # How a home bill's month stands (Tally::HomeBills::Month): "paid on Oct 8, 2026 ·
      # R$ 182.40 · Nubank conta", "due on Oct 10, 2026" or "late since Oct 10, 2026".
      def home_bill_status(entry)
        payment = entry.payment
        text = if payment
          [t("home_bills.paid", date: date(payment[:paid_on])), money(payment[:amount_cents]), payment[:paid_by] || payment[:account_name]].compact.join(" · ")
        else
          t("home_bills.#{entry.status}", date: date(entry.due_on))
        end
        %(<span class="home-bill-#{entry.status}">#{ERB::Util.html_escape(text)}</span>).html_safe
      end

      def source_label(source) = t("sources.#{source}", default: source.to_s)

      # A row dated after today, like an installment on a bill exported early: committed,
      # not spent yet.
      def upcoming?(row) = row[:occurred_on] > Date.today.iso8601

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

      # What a row's adjustment says, for its badge (Tally::Adjustments): "canceled",
      # "reimbursed R$ 30,00", "amount changed", "paid back a purchase"; nil for none.
      def adjustment_label(row)
        if row[:refunds_transaction_id] then t("transactions.adjustment.badge.refund")
        elsif row[:adjustment_kind] == "reimbursed"
          t("transactions.adjustment.badge.reimbursed", amount: money(row[:adjustment_cents], row[:currency]))
        elsif row[:adjustment_kind] then t("transactions.adjustment.badge.#{row[:adjustment_kind]}")
        end
      end
    end
  end
end
