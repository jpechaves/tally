# frozen_string_literal: true

module Tally
  module Actions
    module Review
      class Index < Tally::Action
        def handle(request, response)
          response[:saved] = request.params[:saved].to_s[/\A\d+\z/]&.to_i
          response[:page] = [request.params[:page].to_s[/\A\d{1,6}\z/].to_i, 1].max
        end
      end
    end
  end
end
