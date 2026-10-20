# frozen_string_literal: true

module Tally
  module Actions
    module Plans
      class Show < Tally::Action
        include Deps["repos.plan_repo"]

        def handle(request, response)
          response[:plan] = found(plan_repo, request)
        end
      end
    end
  end
end
