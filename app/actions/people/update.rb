# frozen_string_literal: true

module Tally
  module Actions
    module People
      # Renames someone of the household, and the accounts named after them.
      class Update < Tally::Action
        include Deps["repos.person_repo"]

        def handle(request, response)
          person = person_repo.find(request.params[:id].to_i)
          halt 404 unless person
          halt 422, t("errors.invalid_person") unless person_repo.rename(person.id, request.params[:name].to_s[0, 100])

          response.redirect_to "/accounts#people"
        end
      end
    end
  end
end
