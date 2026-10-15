# frozen_string_literal: true

module Tally
  module Actions
    module Cuts
      class Restore < Tally::Action
        include Deps["routes", "repos.insight_repo"]

        def handle(request, response)
          halt 404 if insight_repo.restore(request.params[:id].to_i).zero?

          response.redirect_to routes.path(:cuts)
        end
      end
    end
  end
end
