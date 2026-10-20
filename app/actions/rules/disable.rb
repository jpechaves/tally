# frozen_string_literal: true

module Tally
  module Actions
    module Rules
      class Disable < Tally::Action
        include Deps["routes", "operations.disable_rule"]

        def handle(request, response)
          result = disable_rule.call(id: request.params[:id].to_i)
          halt 404 if result.failure?

          response.redirect_to routes.path(:rules)
        end
      end
    end
  end
end
