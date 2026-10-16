# frozen_string_literal: true

require "uri"

module Tally
  # Long lists go a page at a time, with links to the pages before and after that keep
  # the list's filters (app/templates/shared/_pages.html.erb).
  #
  #   page = Pagination.page(Pagination.param(params[:page]), total: 250)
  #   page.number  # => 1, of page.count 3
  #   repo.list(limit: page.limit, offset: page.offset)  # or page.slice(items)
  module Pagination
    PER_PAGE = 100

    # One page of a list of +total+ items, +per_page+ at a time.
    Page = Data.define(:number, :count, :total, :per_page) do
      def limit = per_page
      def offset = (number - 1) * per_page

      def previous = (number - 1 if number > 1)
      def next = (number + 1 if number < count)

      # This page of a list already in memory.
      def slice(items) = items.slice(offset, limit) || []
    end

    module_function

    # The page number asked for in a query or a form: 1 when missing or not a number.
    def param(value) = [value.to_s[/\A\d{1,6}\z/].to_i, 1].max

    # The page asked for, kept within the pages there are: past the last page is the last
    # page, and an empty list still has page 1.
    def page(number, total:, per_page: PER_PAGE)
      count = [(total + per_page - 1) / per_page, 1].max
      Page.new(number: number.clamp(1, count), count:, total:, per_page:)
    end

    # Links to the other pages of +base+, keeping the +filters+ that are set.
    #   path("/transactions", account: 3, month: nil).(2)  # => "/transactions?account=3&page=2"
    def path(base, **filters)
      query = filters.reject { |_, value| value.nil? || value.to_s.empty? }
      ->(number) { "#{base}?#{URI.encode_www_form(query.merge(page: number))}" }
    end
  end
end
