# frozen_string_literal: true

module Tally
  # Everything spent on a trip, as one total across accounts (issue #75, docs/architecture.md,
  # section 8.8). Rows bought between its dates, in its accounts (all when none is picked),
  # are in it; your choices add rows from any date (a flight bought weeks before) or take
  # rows out. A card purchase in installments is in or out as a whole, its installments
  # not imported yet included. Rows in another currency (Conta Global) count in reais at
  # what their account's top-ups cost (Tally::TopUps); top-ups are transfers, never counted.
  class Trip
    # A total by category or account: in reais (cents), and in the account's own currency.
    Line = Data.define(:id, :name, :cents, :own_cents, :currency)

    # A card purchase's installments still to come, which no statement has yet.
    Future = Data.define(:description, :count, :cents)

    IOF = /\bIOF\b/i

    attr_reader :rows, :future

    # @param trip [Hash] starts_on, ends_on ("YYYY-MM-DD"), account_ids (empty for all) and
    #   choices ({transaction id => true to add, false to take out})
    # @param rows [Array<Hash>] InsightRepo#trip_rows
    # @param installments [Array<Hash>] InsightRepo#installment_rows
    # @param costs [Hash] account id => TopUps::Cost, for accounts in another currency
    def initialize(trip, rows, installments: [], costs: {})
      @trip = trip
      @costs = costs
      purchases = InstallmentCalendar.series(installments).select { |series| purchase?(series) }
      singles = rows.select { Insights.spending?(_1) && _1[:installment_total].nil? && chosen?(_1) }
      @rows = (singles + purchases.flatten).sort_by { [_1[:occurred_on], _1[:id]] }
      # Keyed by the purchase's latest installment.
      @to_come = purchases.map { InstallmentCalendar::Purchase.of(_1) }.select { _1.left.positive? }.to_h { [_1.id, _1] }
      @future = @to_come.values.map { Future.new(description: _1.description, count: _1.left, cents: _1.cents * _1.left) }
    end

    def ids = rows.map { _1[:id] }

    # In the trip by your choice, not by its date and account.
    def added?(row) = !in_range?(row)

    # What a row cost in reais, positive; nil for another currency without a top-up to price it.
    def reais(row)
      spent = -row[:amount_cents]
      return spent if row[:currency] == Money::DEFAULT_CURRENCY

      @costs[row[:account_id]]&.convert(spent)
    end

    def total_cents = rows.sum { reais(_1) || 0 } + future.sum(&:cents)

    # Spent in each other currency, in that currency.
    def foreign = foreign_rows.group_by { _1[:currency] }.transform_values { |rows| rows.sum { -_1[:amount_cents] } }

    def foreign_reais_cents = foreign_rows.sum { reais(_1) || 0 }

    # Some rows in another currency have no top-up to price them, so the total leaves them out.
    def unpriced = foreign_rows.any? { reais(_1).nil? }

    # IOF on international purchases, net of IOF given back.
    def iof_cents = rows.select { IOF.match?(_1[:description]) }.sum { -_1[:amount_cents] }

    # By top category (a parent with its children), biggest first.
    def by_category
      lines(rows.group_by { _1[:parent_id] || _1[:category_id] }) do |id, group|
        Line.new(id:, name: group.first[:parent_name] || group.first[:category_name], cents: cents(group), own_cents: nil, currency: nil)
      end
    end

    def by_account
      lines(rows.group_by { _1[:account_id] }) do |id, group|
        own = -group.sum { _1[:amount_cents] } + future_cents(group)
        Line.new(id:, name: group.first[:account_name], cents: cents(group), own_cents: own, currency: group.first[:currency])
      end
    end

    private

    def in_range?(row)
      accounts = @trip[:account_ids]
      (@trip[:starts_on]..@trip[:ends_on]).cover?(row[:purchased_on] || row[:occurred_on]) &&
        (accounts.empty? || accounts.include?(row[:account_id]))
    end

    def chosen?(row) = @trip[:choices].fetch(row[:id]) { in_range?(row) }

    # A purchase is in when any installment is and you took none out.
    def purchase?(series) = series.any? { chosen?(_1) } && series.none? { @trip[:choices][_1[:id]] == false }

    def foreign_rows = rows.reject { _1[:currency] == Money::DEFAULT_CURRENCY }

    # In reais, with the installments to come of the purchases among them.
    def cents(group) = group.sum { reais(_1) || 0 } + future_cents(group)

    def future_cents(group) = group.filter_map { @to_come[_1[:id]] }.sum { _1.cents * _1.left }

    def lines(groups, &) = groups.map(&).sort_by { [-_1.cents, _1.name.to_s] }
  end
end
