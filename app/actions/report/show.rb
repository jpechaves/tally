# frozen_string_literal: true

module Tally
  module Actions
    module Report
      class Show < Tally::Action
        def handle(request, response)
          response[:requested_month] = month_param(request.params[:month])
          response[:person_id] = person_param(request.params[:person])
          response[:hide_trips] = request.params[:trips] == "hide"
        end
      end
    end
  end
end
