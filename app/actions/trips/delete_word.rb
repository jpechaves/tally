# frozen_string_literal: true

module Tally
  module Actions
    module Trips
      class DeleteWord < Tally::Action
        include Deps["repos.travel_word_repo"]

        def handle(request, response)
          halt 404 if travel_word_repo.delete(request.params[:id].to_i).zero?

          response.redirect_to "/trips"
        end
      end
    end
  end
end
