# frozen_string_literal: true

module Tally
  module Actions
    module Plans
      class Show < Tally::Action
        include Deps["repos.plan_repo"]

        def handle(request, response)
          plan = plan_repo.find(request.params[:id].to_i)
          halt 404 unless plan

          response[:plan] = plan
        end
      end
    end
  end
end
