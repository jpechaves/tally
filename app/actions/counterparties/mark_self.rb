# frozen_string_literal: true

module Tally
  module Actions
    module Counterparties
      # "This is me" / "Not me": a Pix between you and yourself is a transfer.
      class MarkSelf < Tally::Action
        include Deps["routes", "operations.mark_self"]

        def handle(request, response)
          result = mark_self.call(counterparty_id: request.params[:id].to_i, is_self: request.params[:is_self] == "1")
          halt 404 if result.failure?

          # Back to the same search and page.
          params = request.params
          back = Tally::Pagination.path(routes.path(:counterparties), q: params[:q].to_s.strip[0, 100])
          response.redirect_to back.call(Tally::Pagination.param(params[:page]))
        end
      end
    end
  end
end
