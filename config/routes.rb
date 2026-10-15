# frozen_string_literal: true

module Tally
  class Routes < Hanami::Routes
    root to: "home.show"

    get "/imports", to: "imports.index", as: :imports
    post "/imports", to: "imports.create"
    get "/imports/:id", to: "imports.show", as: :import

    get "/accounts", to: "accounts.index", as: :accounts
    get "/transactions", to: "transactions.index", as: :transactions

    get "/counterparties", to: "counterparties.index", as: :counterparties
    post "/counterparties/:id/self", to: "counterparties.mark_self", as: :mark_self
  end
end
