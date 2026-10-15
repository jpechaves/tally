# frozen_string_literal: true

module Tally
  module Views
    module Budgets
      class Index < Tally::View
        include Deps["repos.plan_repo", "repos.insight_repo", "repos.category_repo"]

        expose :today, decorate: false do
          Date.today
        end

        expose :month do |today, requested_month: nil|
          requested_month || today.strftime("%Y-%m")
        end

        expose :plan do
          plan_repo.active
        end

        expose :categories, decorate: false do
          category_repo.tree.to_h { [_1[:id], _1] }
        end

        # Months to pick from: from the first budget to next month.
        expose :months, decorate: false do |today|
          first = plan_repo.first_budget_month
          current = today.strftime("%Y-%m")
          if first && first <= current
            [first] + Tally::Insights.next_months(first, Tally::Insights.months_between(first, current) + 1)
          else
            [current, Tally::Insights.next_months(current, 1).first].compact.uniq
          end.reverse
        end

        expose :budget_month, decorate: false do |month, plan, categories, today|
          build(month, plan, categories, today)
        end

        # The score of each complete month since the plan started, newest first.
        expose :scores, decorate: false do |plan, categories, today|
          next [] unless plan

          current = today.strftime("%Y-%m")
          count = Tally::Insights.months_between(plan[:starts_month], current)
          next [] unless count.positive?

          months = [plan[:starts_month]] + Tally::Insights.next_months(plan[:starts_month], count - 1)
          months.map { [_1, build(_1, plan, categories, today).score] }.reverse
        end

        expose :next_installments_cents, decorate: false do |month|
          following = Tally::Insights.next_months(month, 1).first
          Tally::InstallmentCalendar.new(insight_repo.installment_rows, from: following).months.fetch(following, 0)
        end

        expose :expense_categories, decorate: false do |categories|
          categories.values.select { _1[:kind] == "expense" && _1[:archived_at].nil? }
        end

        private

        def build(month, plan, categories, today)
          names = categories.transform_values { {name: _1[:name], parent_name: _1[:parent_name]} }
          Tally::BudgetMonth.new(insight_repo.rows(from: month, to: month), month:, budgets: plan_repo.budgets_for(month),
            categories: names, today:, target_cents: plan && plan[:target_cents],
            expected_income_cents: plan ? plan[:baseline_income_cents] : 0)
        end
      end
    end
  end
end
