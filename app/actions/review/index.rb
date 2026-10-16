# frozen_string_literal: true

module Tally
  module Actions
    module Review
      class Index < Tally::Action
        def handle(request, response)
          response[:saved] = request.params[:saved].to_s[/\A\d+\z/]&.to_i
          response[:page] = Tally::Pagination.param(request.params[:page])
        end
      end
    end
  end
end
