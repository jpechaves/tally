# frozen_string_literal: true

module Tally
  module Actions
    module People
      # Adds someone to the household (issue #21), whose statements you then import as theirs.
      class Create < Tally::Action
        include Deps["repos.person_repo"]

        def handle(request, response)
          halt 422, t("errors.invalid_person") unless person_repo.create(request.params[:name].to_s[0, 100])

          response.redirect_to "/accounts#people"
        end
      end
    end
  end
end
