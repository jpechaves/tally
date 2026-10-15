# frozen_string_literal: true

module Tally
  module Actions
    module Counterparties
      class Index < Tally::Action
        def handle(request, response)
          response[:search] = request.params[:q].to_s.strip[0, 100]
          response[:page] = [request.params[:page].to_s[/\A\d{1,6}\z/].to_i, 1].max
        end
      end
    end
  end
end
