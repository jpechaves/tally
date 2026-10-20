# frozen_string_literal: true

module Tally
  module Actions
    module Plans
      # Accepts the proposal with your edits; its limits become the budgets.
      class Accept < Tally::Action
        include Deps["routes", "operations.accept_plan"]

        def handle(request, response)
          proposed = (request.params[:proposed] || {}).to_h.to_h do |category_id, text|
            [category_id.to_s.to_i, parse_amount(text.to_s).cents]
          end
          result = accept_plan.call(id: request.params[:id].to_i, proposed:)
          halt 404 if result.failure? && result.failure == :not_found
          halt 422, t("errors.could_not_save", reason: result.failure) if result.failure?

          response.redirect_to "#{routes.path(:budgets)}?month=#{result.value![:starts_month]}"
        rescue Tally::Money::ParseError
          halt 422, t("errors.invalid_amount")
        end
      end
    end
  end
end
