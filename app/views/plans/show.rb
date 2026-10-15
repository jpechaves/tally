# frozen_string_literal: true

module Tally
  module Views
    module Plans
      class Show < Tally::View
        include Deps["repos.plan_repo", "repos.insight_repo"]

        LEVER_MONTHS = 3

        expose :plan

        expose :lines do |plan|
          plan_repo.lines(plan[:id])
        end

        expose :saved_today_cents do |plan|
          plan[:baseline_income_cents] - plan[:baseline_spending_cents]
        end

        expose :gap_cents do |plan, saved_today_cents|
          plan[:target_cents] - saved_today_cents
        end

        expose :cuts_cents do |lines|
          lines.sum { _1[:baseline_cents] - _1[:proposed_cents] }
        end

        expose :fixed_lines do |lines|
          lines.select { _1[:nature] == "fixed" }
        end

        # Installment purchases ending in the next few months: money each one frees.
        expose :ending_installments do |plan|
          from = plan[:starts_month]
          last = Tally::Insights.next_months(from, LEVER_MONTHS - 1).last
          Tally::InstallmentCalendar.new(insight_repo.installment_rows, from:).purchases.select { _1.ends <= last }
        end
      end
    end
  end
end
