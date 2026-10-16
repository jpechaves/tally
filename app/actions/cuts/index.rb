# frozen_string_literal: true

module Tally
  module Actions
    module Cuts
      class Index < Tally::Action
        def handle(request, response)
          response[:requested_month] = month_param(request.params[:month])
        end
      end
    end
  end
end
