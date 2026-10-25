# frozen_string_literal: true

module Tally
  class Routes < Hanami::Routes
    root to: "home.show"
    get "/assets/:name", to: "assets.show", as: :asset, constraints: {name: /[a-z]+\.(css|js|svg)/}

    post "/locale", to: "locale.update", as: :locale
    post "/theme", to: "theme.update", as: :theme
    get "/debug", to: "debug.show", as: :debug
    post "/debug/export", to: "debug.export", as: :debug_export
    get "/debug/backups/:file", to: "debug.backup", as: :backup, constraints: {file: /[a-z-]+-\d{8}-\d{6}\.sqlite/}

    get "/imports", to: "imports.index", as: :imports
    post "/imports", to: "imports.create"
    get "/imports/:id", to: "imports.show", as: :import

    get "/accounts", to: "accounts.index", as: :accounts
    get "/accounts/:id/report", to: "accounts.report", as: :account_report
    post "/accounts/balance-checks", to: "accounts.check_balance", as: :balance_checks
    post "/balance-checks/:id/delete", to: "accounts.uncheck_balance", as: :delete_balance_check
    post "/people", to: "people.create", as: :people
    post "/people/:id", to: "people.update", as: :person
    get "/transactions", to: "transactions.index", as: :transactions
    post "/transactions/category", to: "transactions.recategorize", as: :recategorize
    get "/transactions/:id", to: "transactions.show", as: :transaction
    post "/transactions/:id", to: "transactions.update"
    post "/transactions/:id/adjustment", to: "transactions.adjust", as: :adjust_transaction
    post "/transactions/:id/adjustment/remove", to: "transactions.unadjust", as: :unadjust_transaction

    get "/counterparties", to: "counterparties.index", as: :counterparties
    get "/counterparties/:id", to: "counterparties.show", as: :counterparty
    post "/counterparties/:id", to: "counterparties.update"
    post "/counterparties/:id/self", to: "counterparties.mark_self", as: :mark_self

    get "/report", to: "report.show", as: :report
    get "/cuts", to: "cuts.index", as: :cuts
    post "/cuts/dismiss", to: "cuts.dismiss", as: :dismiss_cut
    post "/cuts/:id/restore", to: "cuts.restore", as: :restore_cut
    get "/installments", to: "installments.index", as: :installments
    get "/subscriptions", to: "subscriptions.index", as: :subscriptions
    post "/subscriptions/marks", to: "subscriptions.mark", as: :subscription_marks
    post "/subscriptions/marks/:id/remove", to: "subscriptions.unmark", as: :subscription_unmark
    get "/trips", to: "trips.index", as: :trips
    post "/trips", to: "trips.create"
    post "/trips/rows", to: "trips.choose", as: :trip_rows
    get "/trips/:id", to: "trips.show", as: :trip
    post "/trips/:id", to: "trips.update"
    post "/trips/:id/delete", to: "trips.delete", as: :delete_trip
    get "/home-bills", to: "home_bills.index", as: :home_bills
    post "/home-bills", to: "home_bills.create"
    get "/home-bills/:id", to: "home_bills.show", as: :home_bill
    post "/home-bills/:id/delete", to: "home_bills.delete", as: :delete_home_bill
    post "/home-bills/:id/payments", to: "home_bills.pay", as: :home_bill_payments
    post "/home-bills/:id/payments/remove", to: "home_bills.unpay", as: :home_bill_unpay
    post "/home-bills/:id/receipts", to: "home_bills.upload", as: :home_bill_receipts
    get "/receipts/:id", to: "receipts.show", as: :receipt
    post "/receipts/:id/delete", to: "receipts.delete", as: :delete_receipt

    get "/plan", to: "plans.index", as: :plans
    post "/plan", to: "plans.create"
    get "/plan/:id", to: "plans.show", as: :plan
    post "/plan/:id/accept", to: "plans.accept", as: :accept_plan
    post "/plan/:id/delete", to: "plans.delete", as: :delete_plan
    get "/budgets", to: "budgets.index", as: :budgets
    post "/budgets", to: "budgets.update"
    post "/budgets/remove", to: "budgets.remove", as: :remove_budgets

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
