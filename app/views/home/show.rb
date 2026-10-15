# frozen_string_literal: true

module Tally
  module Views
    module Home
      # The dashboard: the latest complete month at a glance, the last year's income
      # against spending, and where the money went.
      class Show < Tally::View
        include Deps["db.gateway", "repos.insight_repo", "repos.transaction_repo"]

        TREND_MONTHS = 12
        TOP_CATEGORIES = 6

        expose :month do
          Tally::Insights.default_month(transaction_repo.months)
        end

        expose :report do |month|
          next unless month

          from = Tally::Insights.previous_months(month, Tally::Report::AVERAGE_MONTHS).first
          Tally::Report.new(insight_repo.rows(from:, to: month), month:)
        end

        # Income and spending per month up to `month`, from the first month with rows.
        expose :trend, decorate: false do |month|
          next [] unless month

          months = Tally::Insights.previous_months(month, TREND_MONTHS - 1) + [month]
          totals = Tally::Insights.monthly(insight_repo.rows(from: months.first, to: month), months)
          totals.drop_while { _1[:income_cents].zero? && _1[:spending_cents].zero? }
        end

        expose :top_categories, decorate: false do |report|
          report ? report.categories.first(TOP_CATEGORIES) : []
        end

        # The SQLite settings actually in effect, so a fresh install (e.g. on the Pi) can be
        # checked at a glance.
        expose :database do
          db = gateway.connection
          pragma = ->(name) { db.fetch("PRAGMA #{name}").single_value }

          {
            sqlite_version: db.fetch("SELECT sqlite_version()").single_value,
            journal_mode: pragma.("journal_mode"),
            foreign_keys: pragma.("foreign_keys") == 1 ? "on" : "off",
            synchronous: {0 => "off", 1 => "normal", 2 => "full", 3 => "extra"}.fetch(pragma.("synchronous")),
            busy_timeout: "#{pragma.("busy_timeout")} ms"
          }
        end
      end
    end
  end
end
