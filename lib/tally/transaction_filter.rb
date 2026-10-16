# frozen_string_literal: true

require "uri"

module Tally
  # What the transactions page is narrowed to. It is read from the page's query and
  # written back into links, so any page can point at the rows behind one of its numbers
  # (docs/architecture.md, section 8.6):
  #
  #   filter = TransactionFilter.parse(params)  # ?category=12&month=2026-08
  #   transaction_repo.list(filter)             # TransactionRepo applies it
  #   TransactionFilter.new(category: 12, month: "2026-08", kind: "spending").path
  #   # => "/transactions?month=2026-08&category=12&kind=spending"
  #
  # Every attribute is optional; nil means "any".
  #   account   an account id
  #   month     "YYYY-MM"
  #   category  a category id, which takes in its children when it is a parent, or NONE
  #   kind      one of KINDS: "spending" and "income" are the rows the report counts as
  #             such, so their totals match it; "transfer" is the transfers
  TransactionFilter = Data.define(:account, :month, :category, :kind) do
    def initialize(account: nil, month: nil, category: nil, kind: nil) = super

    # The query string's parameters that are set, in a stable order.
    def query = to_h.compact

    def any? = !query.empty?

    def path = any? ? "#{self.class::PATH}?#{URI.encode_www_form(query)}" : self.class::PATH

    # Links to the other pages of the filtered list (Tally::Pagination).
    def pages = Pagination.path(self.class::PATH, **query)

    # Totals shown as spending (positive) instead of a net.
    def spending? = kind == "spending"
  end

  class TransactionFilter
    PATH = "/transactions"

    # The category filter for rows with no category.
    NONE = "none"

    KINDS = %w[spending income transfer].freeze

    ID = /\A\d{1,9}\z/
    MONTH = /\A\d{4}-(0[1-9]|1[0-2])\z/

    # Reads the filters from a request's params; a value that isn't valid is ignored.
    def self.parse(params)
      new(
        account: params[:account].to_s[ID]&.to_i,
        month: params[:month].to_s[MONTH],
        category: (params[:category].to_s == NONE) ? NONE : params[:category].to_s[ID]&.to_i,
        kind: KINDS.find { _1 == params[:kind].to_s }
      )
    end
  end
end
