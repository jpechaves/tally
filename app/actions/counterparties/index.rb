# frozen_string_literal: true

module Tally
  module Actions
    module Counterparties
      class Index < Tally::Action
        def handle(request, response)
          response[:search] = request.params[:q].to_s.strip[0, 100]
          response[:page] = Tally::Pagination.param(request.params[:page])
        end
      end
    end
  end
end
