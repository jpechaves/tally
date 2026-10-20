# frozen_string_literal: true

module Tally
  module Actions
    module Budgets
      class Index < Tally::Action
        def handle(request, response)
          response[:requested_month] = month_param(request.params[:month])
          response[:error_code] = code_param(request.params[:error])
        end
      end
    end
  end
end
