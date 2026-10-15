# frozen_string_literal: true

module Tally
  module Actions
    module Cuts
      # Hides a suggestion for good: the same payee or category stays quiet.
      class Dismiss < Tally::Action
        include Deps["routes", "repos.insight_repo"]

        def handle(request, response)
          key = request.params[:key].to_s.strip
          halt 422, "Missing key" if key.empty?

          insight_repo.dismiss(key:, title: request.params[:title].to_s.strip[0, 300])
          month = request.params[:month].to_s[/\A\d{4}-\d{2}\z/]
          response.redirect_to month ? "#{routes.path(:cuts)}?month=#{month}" : routes.path(:cuts)
        end
      end
    end
  end
end
