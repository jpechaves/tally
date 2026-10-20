# frozen_string_literal: true

module Tally
  module Actions
    module Categories
      class Update < Tally::Action
        include Deps["routes", "operations.save_category"]

        def handle(request, response)
          params = request.params
          result = save_category.call(id: params[:id].to_i,
            name: params[:name],
            nature: params[:nature].to_s,
            max_cut_pct: params[:max_cut_pct].to_s[/\A\d+\z/]&.to_i,
            archived: params[:archived] == "1")
          halt 404 if result.failure? && result.failure == :not_found

          path = routes.path(:categories)
          response.redirect_to result.failure? ? "#{path}?error=#{result.failure}" : path
        end
      end
    end
  end
end
