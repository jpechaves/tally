# frozen_string_literal: true

module Tally
  # "What can I cut?" (docs/architecture.md, section 8.3). Each signal looks at one month
  # and its history and suggests something with an estimate in cents per month. They are
  # suggestions, not judgments: each has a key, and a dismissed key stays hidden.
  class Cuts
    Suggestion = Data.define(:key, :signal, :title, :detail, :monthly_cents, :ids)

    BIG_SHARE_PCT = 5
    GROWTH_PCT = 25
    GROWTH_MIN_CENTS = 10_000
    RECURRING_MONTHS = 4
    RECURRING_MIN_MONTHS = 3
    RECURRING_TOLERANCE_PCT = 10
    SMALL_CENTS = 5_000
    SMALL_MIN_COUNT = 8
    DUPLICATE_DAYS = 1
    DUPLICATE_MAX_CHARGES = 3
    DEBT_PARENT = "Dívidas"

    SIGNALS = {
      "big" => "Big discretionary category",
      "growth" => "Growing",
      "recurring" => "Recurring charge",
      "small" => "Many small purchases",
      "fees" => "Fees and interest",
      "duplicate" => "Possible duplicate charge",
      "installments" => "New installments"
    }.freeze

    # @param rows [Array<Hash>] rows of `month` and the months before it
    # @param dismissed [Enumerable<String>] keys you dismissed
    def initialize(rows, month:, dismissed: [])
      @month = month
      @dismissed = dismissed.to_set
      @by_month = rows.select { Insights.spending?(_1) }.group_by { Insights.month_of(_1) }
      @rows = @by_month.fetch(month, [])
      @spending = Insights.spent_cents(@rows)
    end

    # @return [Array<Suggestion>] biggest estimate first, dismissed ones left out
    def suggestions
      all = big + growth + recurring + small + fees + duplicates + installments
      all.reject { @dismissed.include?(_1.key) }.sort_by { [-_1.monthly_cents, _1.key] }
    end

    private

    def money(cents) = Money.new(cents).format

    # Rows by category, without installments after the first: those are already
    # committed, and cutting the category can't save them.
    def by_category
      @rows.select { _1[:category_id] && _1[:installment_number].to_i <= 1 }.group_by { _1[:category_id] }
    end

    # Rows that aren't installments: an installment repeats every month by design, so it
    # is neither a recurring charge nor a duplicate.
    def single(rows) = rows.reject { _1[:installment_total] }

    def purchases(count) = count == 1 ? "1 purchase" : "#{count} purchases"

    # Discretionary categories over 5% of the month's spending. The estimate is what the
    # category's maximum cut would save.
    def big
      by_category.filter_map do |id, rows|
        first = rows.first
        cents = Insights.spent_cents(rows)
        next unless first[:nature] == "discretionary" && cents * 100 > @spending * BIG_SHARE_PCT

        Suggestion.new(
          key: "big:category:#{id}", signal: "big",
          title: "#{first[:category_name]}: #{purchases(rows.size)}, #{money(cents)}",
          detail: "#{Insights.share(cents, @spending)}% of the month. Cutting it by #{first[:max_cut_pct]}% saves this much.",
          monthly_cents: cents * first[:max_cut_pct].to_i / 100, ids: rows.map { _1[:id] }
        )
      end
    end

    # Categories this month over their 3-month average by 25% and R$ 100. Needs all three
    # months of history.
    def growth
      history = Insights.previous_months(@month, 3)
      return [] unless history.all? { @by_month.key?(_1) }

      by_category.filter_map do |id, rows|
        cents = Insights.spent_cents(rows)
        average = Insights.average(history.map { |m| Insights.spent_cents(@by_month[m].select { _1[:category_id] == id }) })
        growth = cents - average
        next unless average.positive? && growth * 100 > average * GROWTH_PCT && growth >= GROWTH_MIN_CENTS

        Suggestion.new(
          key: "growth:category:#{id}:#{@month}", signal: "growth",
          title: "#{rows.first[:category_name]}: #{money(cents)}, up from #{money(average)} a month",
          detail: "#{((growth * 100.0) / average).round}% over the average of #{history.first} to #{history.last}.",
          monthly_cents: growth, ids: rows.map { _1[:id] }
        )
      end
    end

    # The same payee this month and in 3 of the last 4 months, each month within 10% of
    # the typical (median) amount: subscriptions, gym, phone, a monthly Pix. The estimate
    # is this month's charge. Fees are left out: the fees signal nets them against their
    # discounts (a card fee and its "Redução Mensalidade").
    def recurring
      return [] unless @rows.any?

      months = Insights.previous_months(@month, RECURRING_MONTHS - 1) + [@month]

      charges = ->(rows) { single(rows).reject { _1[:kind] == "fee" } }
      charges.(@rows).group_by { Insights.payee_key(_1) }.filter_map do |key, rows|
        totals = months.to_h { |m| [m, Insights.spent_cents(charges.(@by_month.fetch(m, [])).select { Insights.payee_key(_1) == key })] }
          .select { |_, cents| cents.positive? }
        next if totals.size < RECURRING_MIN_MONTHS

        typical = totals.values.sort[totals.size / 2]
        next unless totals.values.all? { (_1 - typical).abs * 100 <= typical * RECURRING_TOLERANCE_PCT }

        current = totals.fetch(@month, 0)
        next unless current.positive?

        Suggestion.new(
          key: "recurring:#{key}", signal: "recurring",
          title: "#{Insights.payee_label(rows.first)}: #{money(current)} a month",
          detail: "Charged in #{totals.size} of the last #{RECURRING_MONTHS} months. Still worth it?",
          monthly_cents: current, ids: rows.map { _1[:id] }
        )
      end
    end

    # 8 or more purchases under R$ 50 at the same payee in a month.
    def small
      @rows.select { _1[:kind] == "purchase" && -_1[:amount_cents] < SMALL_CENTS }
        .group_by { Insights.payee_key(_1) }.filter_map do |key, rows|
          next if rows.size < SMALL_MIN_COUNT

          cents = Insights.spent_cents(rows)
          Suggestion.new(
            key: "small:#{key}", signal: "small",
            title: "#{Insights.payee_label(rows.first)}: #{rows.size} charges, #{money(cents)}",
            detail: "Small amounts add up: #{money(cents / rows.size)} on average.",
            monthly_cents: cents, ids: rows.map { _1[:id] }
          )
        end
    end

    # Card fees, IOF, interest and financing: money that buys nothing.
    def fees
      rows = @rows.select { _1[:kind] == "fee" || _1[:parent_name] == DEBT_PARENT || _1[:category_name] == DEBT_PARENT }
      cents = Insights.spent_cents(rows)
      return [] unless cents.positive?

      [Suggestion.new(
        key: "fees:#{@month}", signal: "fees",
        title: "Fees, interest and financing: #{money(cents)}",
        detail: "#{rows.size} rows. Ask for the card fee to be waived, or pay debts down early.",
        monthly_cents: cents, ids: rows.map { _1[:id] }
      )]
    end

    # The same payee and amount twice on the same or the next day. A payee charging that
    # amount more than 3 times in the month (parking every day) is a habit, not a mistake.
    # Dismissing it (two memberships, say) keeps that payee and amount quiet.
    def duplicates
      single(@rows).select { _1[:kind] == "purchase" }.group_by { [Insights.payee_key(_1), _1[:amount_cents]] }
        .filter_map do |(key, amount), rows|
          next if rows.size > DUPLICATE_MAX_CHARGES

          dates = rows.map { Date.iso8601(_1[:occurred_on]) }.sort
          next unless dates.each_cons(2).any? { |a, b| (b - a) <= DUPLICATE_DAYS }

          Suggestion.new(
            key: "duplicate:#{key}:#{amount}", signal: "duplicate",
            title: "#{Insights.payee_label(rows.first)}: #{money(-amount)} charged #{rows.size} times",
            detail: "On #{rows.map { _1[:occurred_on] }.sort.uniq.join(", ")}. Check that it isn't a double charge.",
            monthly_cents: -amount * (rows.size - 1), ids: rows.map { _1[:id] }
          )
        end
    end

    # Installment purchases whose first installment is this month: they add to the next
    # bills too. One suggestion for the month, listing them.
    def installments
      rows = @rows.select { _1[:installment_number] == 1 && _1[:installment_total].to_i > 1 }
      return [] if rows.empty?

      cents = Insights.spent_cents(rows)
      later = rows.sum { -_1[:amount_cents] * (_1[:installment_total] - 1) }
      names = rows.sort_by { _1[:amount_cents] }.first(5).map { "#{_1[:description]} (#{_1[:installment_total]}×)" }
      [Suggestion.new(
        key: "installments:#{@month}", signal: "installments",
        title: "#{purchases(rows.size)} in installments: #{money(cents)} this month",
        detail: "Commits #{money(later)} more to the next bills. Biggest: #{names.join(", ")}.",
        monthly_cents: cents, ids: rows.map { _1[:id] }
      )]
    end
  end
end
