# frozen_string_literal: true

module Tally
  module Repos
    # Savings plans and their lines, and the monthly budgets an accepted plan writes.
    class PlanRepo < Tally::DB::Repo
      def find(id) = savings_plans.dataset.where(id:).first

      def active = savings_plans.dataset.where(status: "active").order(Sequel.desc(:id)).first

      def all = savings_plans.dataset.order(Sequel.desc(:id)).all

      # @param planner [Tally::Planner]
      # @return [Integer] the draft's id
      def create_draft(planner, starts_month:)
        id = savings_plans.dataset.insert(
          target_cents: planner.target_cents, baseline_from: planner.months.first, baseline_to: planner.months.last,
          baseline_income_cents: planner.income_cents, baseline_spending_cents: planner.spending_cents,
          starts_month:, status: "draft", shortfall_cents: planner.shortfall_cents
        )
        planner.lines.each do |line|
          savings_plan_lines.dataset.insert(savings_plan_id: id, category_id: line.category_id,
            baseline_cents: line.baseline_cents, max_cut_cents: line.max_cut_cents, proposed_cents: line.proposed_cents)
        end
        id
      end

      # The plan's lines with their category, biggest baseline first.
      def lines(plan_id)
        savings_plan_lines.dataset.where(savings_plan_id: plan_id)
          .join(:categories, id: :category_id)
          .left_join(Sequel[:categories].as(:parents), id: Sequel[:categories][:parent_id])
          .select_all(:savings_plan_lines)
          .select_append(Sequel[:categories][:name], Sequel[:categories][:nature], Sequel[:parents][:name].as(:parent_name))
          .order(Sequel.desc(:baseline_cents), Sequel[:categories][:name]).all
      end

      # Saves your edits to the proposal and makes it the active plan: the one before it
      # is replaced, and its limits become the budgets from the plan's first month.
      #
      # @param proposed [Hash{Integer => Integer}] category id => monthly limit in cents
      def accept(plan_id, proposed:)
        plan = find(plan_id)
        proposed.each do |category_id, cents|
          savings_plan_lines.dataset.where(savings_plan_id: plan_id, category_id:).update(proposed_cents: cents)
        end
        savings_plans.dataset.where(status: "active").update(status: "replaced", updated_at: Repos.now)
        savings_plans.dataset.where(id: plan_id).update(status: "active", updated_at: Repos.now)

        lines(plan_id).each do |line|
          set_budget(line[:category_id], plan[:starts_month], line[:proposed_cents], savings_plan_id: plan_id)
        end
      end

      # --- Budgets ----------------------------------------------------------------------

      # A budget row applies from its month until the category's next row.
      def set_budget(category_id, month, amount_cents, savings_plan_id: nil)
        budgets.dataset.insert_conflict(
          target: %i[category_id month],
          update: {amount_cents: Sequel[:excluded][:amount_cents], savings_plan_id: Sequel[:excluded][:savings_plan_id],
                   updated_at: Repos.now}
        ).insert(category_id:, month:, amount_cents:, savings_plan_id:)
      end

      # Category id => the limit in force in `month`: each category's latest row at or
      # before it.
      def budgets_for(month)
        latest = budgets.dataset.unordered.where(Sequel[:budgets][:month] <= month)
          .group(:category_id).select(:category_id) { max(:month).as(:month) }
        budgets.dataset.join(latest.as(:latest), category_id: :category_id, month: :month)
          .select_hash(Sequel[:budgets][:category_id], Sequel[:budgets][:amount_cents])
      end

      # The first month any budget applies to, or nil.
      def first_budget_month = budgets.dataset.min(:month)
    end
  end
end
