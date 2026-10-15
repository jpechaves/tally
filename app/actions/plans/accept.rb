# frozen_string_literal: true

module Tally
  module Actions
    module Plans
      # Accepts the proposal with your edits; its limits become the budgets.
      class Accept < Tally::Action
        include Deps["routes", "operations.accept_plan"]

        def handle(request, response)
          proposed = (request.params[:proposed] || {}).to_h.to_h do |category_id, text|
            [category_id.to_s.to_i, Tally::Money.parse(text.to_s, decimal: ",").cents]
          end
          result = accept_plan.(id: request.params[:id].to_i, proposed:)
          halt 404 if result.failure? && result.failure == :not_found
          halt 422, "Could not accept: #{result.failure}" if result.failure?

          response.redirect_to "#{routes.path(:budgets)}?month=#{result.value![:starts_month]}"
        rescue Tally::Money::ParseError => e
          halt 422, "Could not accept: #{e.message}"
        end
      end
    end
  end
end
