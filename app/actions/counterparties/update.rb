# frozen_string_literal: true

module Tally
  module Actions
    module Counterparties
      # Saves your display name and note for a counterparty (issue #37). Imports never
      # change them, and rules keep matching the bank's name.
      class Update < Tally::Action
        include Deps["routes", "repos.counterparty_repo"]

        def handle(request, response)
          id = request.params[:id].to_i
          halt 404 unless counterparty_repo.find(id)

          params = request.params
          counterparty_repo.set_label(id, display_name: params[:display_name].to_s[0, 200], note: params[:note].to_s[0, 500])
          response.redirect_to back_param(params[:back]) || routes.path(:counterparty, id:)
        end
      end
    end
  end
end
