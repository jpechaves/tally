# frozen_string_literal: true

module Tally
  module Actions
    module Review
      class Index < Tally::Action
        def handle(request, response)
          response[:saved] = request.params[:saved].to_s[/\A\d+\z/]&.to_i
          response[:page] = Review.page(request.params[:page])
        end
      end

      # A page number from the query or a form, 1 when missing or not a number.
      def self.page(param) = [param.to_s[/\A\d{1,6}\z/].to_i, 1].max
    end
  end
end
