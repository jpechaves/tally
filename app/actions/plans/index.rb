# frozen_string_literal: true

module Tally
  module Actions
    module Plans
      class Index < Tally::Action
        def handle(request, response)
          response[:error_code] = code_param(request.params[:error])
          response[:notice_code] = code_param(request.params[:notice])
        end
      end
    end
  end
end
