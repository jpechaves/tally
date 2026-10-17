# frozen_string_literal: true

module Tally
  module Repos
    # Savings plans and their lines, and the monthly budgets an accepted plan writes.
    class PlanRepo < Tally::DB::Repo
      def find(id) = savings_plans.dataset.where(id:).first

      def active = savings_plans.dataset.where(status: "active").order(Sequel.desc(:id)).first

      def all = savings_plans.dataset.order(Sequel.desc(:id)).all

      # The newest plan still waiting to be accepted, or nil.
      def latest_draft = savings_plans.dataset.where(status: "draft").order(Sequel.desc(:id)).first

      # Where you are from a plan to budgets (the steps on /plan and /budgets): 1 with no
      # plan, 2 with a draft to accept, 3 once a plan is accepted.
      def step
        if active then 3
        elsif latest_draft then 2
        else 1
        end
      end

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

      # Deletes a plan and its lines. The budgets it wrote are removed with it when
      # `remove_budgets`, which takes them back to what was there before the plan;
      # otherwise they stay, as if you had set them by hand. Transactions and categories
      # are never touched.
      #
      # @return [Integer] how many budget rows the plan had written
      def delete(plan_id, remove_budgets:)
        written = budgets.dataset.where(savings_plan_id: plan_id)
        count = remove_budgets ? written.delete : written.update(savings_plan_id: nil, updated_at: Repos.now)
        savings_plans.dataset.where(id: plan_id).delete
        count
      end

      # How many budget rows the plan wrote that are still its own (a limit you edit by hand
      # in the plan's first month becomes yours).
      def budget_count(plan_id) = budget_counts.fetch(plan_id, 0)

      # Plan id => budget_count, for every plan that still has budgets.
      def budget_counts
        budgets.dataset.where(removed: 0).exclude(savings_plan_id: nil).group_and_count(:savings_plan_id).as_hash(:savings_plan_id, :count)
      end

      # --- Budgets ----------------------------------------------------------------------

      # A budget row applies from its month until the category's next row.
      def set_budget(category_id, month, amount_cents, savings_plan_id: nil)
        budgets.dataset.insert_conflict(
          target: %i[category_id month],
          update: {amount_cents: Sequel[:excluded][:amount_cents], savings_plan_id: Sequel[:excluded][:savings_plan_id],
                   removed: 0, updated_at: Repos.now}
        ).insert(category_id:, month:, amount_cents:, savings_plan_id:)
      end

      # Ends a category's budget from `month` on: its rows from then are deleted, and a
      # removed row stops the one before (the months that one covered keep their limit).
      def remove_budget(category_id, month)
        rows = budgets.dataset.where(category_id:)
        rows.where(Sequel[:month] >= month).delete
        before = rows.where(Sequel[:month] < month).reverse(:month).first
        return unless before && before[:removed].zero?

        budgets.dataset.insert(category_id:, month:, amount_cents: 0, removed: 1)
      end

      # Every category that has ever had a budget.
      def budgeted_category_ids = budgets.dataset.distinct.select_map(:category_id)

      # Category id => the limit in force in `month`: each category's latest row at or
      # before it, unless that row removed the budget.
      def budgets_for(month)
        latest = budgets.dataset.unordered.where(Sequel[:budgets][:month] <= month)
          .group(:category_id).select(:category_id) { max(:month).as(:month) }
        budgets.dataset.join(latest.as(:latest), category_id: :category_id, month: :month)
          .where(Sequel[:budgets][:removed] => 0)
          .select_hash(Sequel[:budgets][:category_id], Sequel[:budgets][:amount_cents])
      end

      # The first month any budget applies to, or nil.
      def first_budget_month = budgets.dataset.where(removed: 0).min(:month)
    end
  end
end
