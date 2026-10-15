# frozen_string_literal: true

module Tally
  module Actions
    module Categories
      class Create < Tally::Action
        include Deps["routes", "operations.save_category"]

        def handle(request, response)
          params = request.params
          result = save_category.(
            name: params[:name],
            parent_id: params[:parent_id].to_s[/\A\d+\z/]&.to_i,
            kind: params[:kind].to_s,
            nature: params[:nature].to_s
          )

          path = routes.path(:categories)
          response.redirect_to result.failure? ? "#{path}?error=#{result.failure}" : path
        end
      end
    end
  end
end
