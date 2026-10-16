# frozen_string_literal: true

module Tally
  module Actions
    module Plans
      class Index < Tally::Action
        def handle(request, response)
          response[:error_code] = request.params[:error].to_s[/\A[a-z_]+\z/]
          response[:notice_code] = request.params[:notice].to_s[/\A[a-z_]+\z/]
        end
      end
    end
  end
end
