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
  #   nature    a category nature, or UNSET for rows whose category has none (or no category)
  #   payee     who was paid, as Tally::Review.key groups rows: "counterparty:12", or
  #             "description:padaria exemplo" for rows without a counterparty
  #   purchase  the id of any installment of a card purchase, for all its installments
  #             (Tally::InstallmentCalendar.series)
  #   trip      a trip's id, for its rows (Tally::Trip)
  #   q         a search: rows whose amount is it (Tally::Search.amount), or whose texts
  #             have every word of it (TransactionRepo)
  TransactionFilter = Data.define(:account, :month, :category, :kind, :nature, :payee, :purchase, :trip, :q) do
    def initialize(account: nil, month: nil, category: nil, kind: nil, nature: nil, payee: nil, purchase: nil, trip: nil, q: nil) = super

    # The query string's parameters that are set, in a stable order.
    def query = to_h.compact

    def any? = !query.empty?

    # The filters the page's form has no field for, which it carries along unchanged.
    def carried = query.except(*self.class::FORM_FIELDS)

    def path = any? ? "#{self.class::PATH}?#{URI.encode_www_form(query)}" : self.class::PATH

    # Links to the other pages of the filtered list (Tally::Pagination), keeping the page
    # it was reached from (+back+), if any.
    def pages(back: nil) = Pagination.path(self.class::PATH, **query, back:)

    # Totals shown as spending (positive) instead of a net.
    def spending? = kind == "spending"
  end

  class TransactionFilter
    PATH = "/transactions"

    # The category filter for rows with no category.
    NONE = "none"

    KINDS = %w[spending income transfer].freeze

    # The nature filter for rows whose category has no nature, as the report calls them.
    UNSET = "unset"
    NATURES = (Categories::NATURES + [UNSET]).freeze

    # Filters with a field of their own in the transactions page's form.
    FORM_FIELDS = %i[account month category kind q].freeze

    # The longest search read; the rest is dropped.
    SEARCH_MAX = 100

    ID = /\A\d{1,9}\z/
    MONTH = Insights::MONTH
    PAYEE = /\A(counterparty:\d{1,9}|description:[^\n]{1,200})\z/

    # Reads the filters from a request's params; a value that isn't valid is ignored.
    def self.parse(params)
      new(
        account: params[:account].to_s[ID]&.to_i,
        month: params[:month].to_s[MONTH],
        category: (params[:category].to_s == NONE) ? NONE : params[:category].to_s[ID]&.to_i,
        kind: KINDS.find { _1 == params[:kind].to_s },
        nature: NATURES.find { _1 == params[:nature].to_s },
        payee: params[:payee].to_s[PAYEE],
        purchase: params[:purchase].to_s[ID]&.to_i,
        trip: params[:trip].to_s[ID]&.to_i,
        q: params[:q].to_s.strip[0, SEARCH_MAX].then { _1 unless _1.empty? }
      )
    end
  end
end
