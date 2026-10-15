# frozen_string_literal: true

module Tally
  module Actions
    module Imports
      class Show < Tally::Action
        include Deps["repos.import_repo"]

        def handle(request, response)
          import = import_repo.find(request.params[:id].to_i)
          halt 404 unless import

          response[:import] = import
        end
      end
    end
  end
end
