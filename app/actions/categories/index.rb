# frozen_string_literal: true

module Tally
  module Actions
    module Categories
      class Index < Tally::Action
        def handle(request, response)
          response[:error_code] = code_param(request.params[:error])
        end
      end
    end
  end
end
