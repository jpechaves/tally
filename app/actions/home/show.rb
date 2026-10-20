# frozen_string_literal: true

module Tally
  module Actions
    module Home
      class Show < Tally::Action
        def handle(request, response)
          response[:person_id] = person_param(request.params[:person])
        end
      end
    end
  end
end
