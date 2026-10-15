# frozen_string_literal: true

module Tally
  class Routes < Hanami::Routes
    root to: "home.show"

    get "/imports", to: "imports.index", as: :imports
    post "/imports", to: "imports.create"
    get "/imports/:id", to: "imports.show", as: :import

    get "/accounts", to: "accounts.index", as: :accounts
    get "/transactions", to: "transactions.index", as: :transactions
    get "/transactions/:id", to: "transactions.show", as: :transaction
    post "/transactions/:id", to: "transactions.update"

    get "/counterparties", to: "counterparties.index", as: :counterparties
    post "/counterparties/:id/self", to: "counterparties.mark_self", as: :mark_self

    get "/report", to: "report.show", as: :report
    get "/cuts", to: "cuts.index", as: :cuts
    post "/cuts/dismiss", to: "cuts.dismiss", as: :dismiss_cut
    post "/cuts/:id/restore", to: "cuts.restore", as: :restore_cut
    get "/installments", to: "installments.index", as: :installments

    get "/plan", to: "plans.index", as: :plans
    post "/plan", to: "plans.create"
    get "/plan/:id", to: "plans.show", as: :plan
    post "/plan/:id/accept", to: "plans.accept", as: :accept_plan
    get "/budgets", to: "budgets.index", as: :budgets
    post "/budgets", to: "budgets.update"

    get "/review", to: "review.index", as: :review
    post "/review", to: "review.assign"

    get "/categories", to: "categories.index", as: :categories
    post "/categories", to: "categories.create"
    post "/categories/:id", to: "categories.update", as: :category

    get "/rules", to: "rules.index", as: :rules
    post "/rules", to: "rules.create"
    post "/rules/:id/disable", to: "rules.disable", as: :disable_rule
  end
end
