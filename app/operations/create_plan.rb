# frozen_string_literal: true

module Tally
  module Operations
    # Builds a draft savings plan for "save X a month" from the last complete months
    # (docs/architecture.md, 8.4). You review and edit it before accepting.
    class CreatePlan < Tally::Operation
      include Deps["repos.insight_repo", "repos.plan_repo"]

      BASELINE_MONTHS = 3

      # @param starts_month [String] "YYYY-MM": the first month its budgets apply to
      # @param today [Date] decides which months are complete
      # @return [Integer] the draft's id
      def call(target_cents:, starts_month:, today: Date.today)
        step Failure(:invalid_target) unless target_cents.is_a?(Integer) && target_cents.positive?

        months = Insights.previous_months(today.strftime("%Y-%m"), BASELINE_MONTHS)
        rows = insight_repo.rows(from: months.first, to: months.last, through: today)
        step Failure(:no_data) if rows.empty?

        planner = Planner.new(rows, months:, target_cents:)
        plan_repo.create_draft(planner, starts_month:)
      end
    end
  end
end
