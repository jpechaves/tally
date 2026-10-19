# frozen_string_literal: true

module Tally
  module Actions
    module Subscriptions
      class Unmark < Tally::Action
        include Deps["routes", "repos.subscription_repo"]

        def handle(request, response)
          halt 404 if subscription_repo.unmark(request.params[:id].to_i).zero?

          response.redirect_to routes.path(:subscriptions)
        end
      end
    end
  end
end
