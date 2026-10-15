# frozen_string_literal: true

module Tally
  module Actions
    module Cuts
      class Index < Tally::Action
        def handle(request, response)
          response[:requested_month] = request.params[:month].to_s[/\A\d{4}-(0[1-9]|1[0-2])\z/]
        end
      end
    end
  end
end
