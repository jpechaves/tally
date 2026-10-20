# frozen_string_literal: true

module Tally
  module Actions
    module Review
      # A category for one group of the review list.
      class Assign < Tally::Action
        include Deps["routes", "operations.assign_category"]

        def handle(request, response)
          params = request.params
          always = params[:always] == "1"
          result = assign_category.call(ids: params[:ids].to_s.split(",").grep(/\A\d+\z/).map(&:to_i),
            category_id: params[:category_id].to_i,
            always:,
            counterparty_id: always ? params[:counterparty_id].to_s[/\A\d+\z/]&.to_i : nil,
            pattern: if always
                       params[:pattern].to_s.then { _1.empty? ? nil : _1 }
                     end)
          halt 422, t("errors.could_not_save", reason: result.failure) if result.failure?

          # Back to the same page: the groups after the saved one move up into it.
          response.redirect_to "#{routes.path(:review)}?page=#{Tally::Pagination.param(params[:page])}&saved=#{result.value!}"
        end
      end
    end
  end
end
