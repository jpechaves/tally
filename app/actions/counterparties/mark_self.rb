# frozen_string_literal: true

module Tally
  module Actions
    module Counterparties
      # "This is me" / "Not me": a Pix between you and yourself is a transfer.
      class MarkSelf < Tally::Action
        include Deps["routes", "operations.mark_self"]

        def handle(request, response)
          result = mark_self.(counterparty_id: request.params[:id].to_i, is_self: request.params[:is_self] == "1")
          halt 404 if result.failure?

          response.redirect_to routes.path(:counterparties)
        end
      end
    end
  end
end
