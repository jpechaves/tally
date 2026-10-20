# frozen_string_literal: true

module Tally
  module Actions
    module Rules
      class Index < Tally::Action
        def handle(request, response)
          response[:error_code] = code_param(request.params[:error])
        end
      end
    end
  end
end
