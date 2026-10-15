# frozen_string_literal: true

module Tally
  module Actions
    module Review
      class Index < Tally::Action
        def handle(request, response)
          response[:saved] = request.params[:saved].to_s[/\A\d+\z/]&.to_i
        end
      end
    end
  end
end
