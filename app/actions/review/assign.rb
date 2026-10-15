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
          result = assign_category.(
            ids: params[:ids].to_s.split(",").grep(/\A\d+\z/).map(&:to_i),
            category_id: params[:category_id].to_i,
            always:,
            counterparty_id: always ? params[:counterparty_id].to_s[/\A\d+\z/]&.to_i : nil,
            pattern: always ? params[:pattern].to_s.then { _1.empty? ? nil : _1 } : nil
          )
          halt 422, t("errors.could_not_save", reason: result.failure) if result.failure?

          response.redirect_to "#{routes.path(:review)}?saved=#{result.value!}"
        end
      end
    end
  end
end
