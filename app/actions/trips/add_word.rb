# frozen_string_literal: true

module Tally
  module Actions
    module Trips
      # Adds a word or merchant name to the travel list (trip suggestions).
      class AddWord < Tally::Action
        include Deps["repos.travel_word_repo"]

        def handle(request, response)
          word = request.params[:word].to_s.strip[0, 100]
          halt 422, t("errors.invalid_travel_word") if Tally::Search.fold(word).empty?

          travel_word_repo.add(word)
          response.redirect_to "/trips"
        end
      end
    end
  end
end
