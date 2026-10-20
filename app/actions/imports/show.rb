# frozen_string_literal: true

module Tally
  module Actions
    module Imports
      class Show < Tally::Action
        include Deps["repos.import_repo"]

        def handle(request, response)
          response[:import] = found(import_repo, request)
        end
      end
    end
  end
end
