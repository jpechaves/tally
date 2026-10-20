# frozen_string_literal: true

module Tally
  module Actions
    module Counterparties
      # "This is me" / "Not me", or who of the household it is when there are several
      # people (issue #21): a Pix between people of the household is a transfer.
      class MarkSelf < Tally::Action
        include Deps["routes", "operations.mark_self"]

        def handle(request, response)
          person_id = request.params[:person].to_s[/\A\d{1,9}\z/]&.to_i
          result = mark_self.call(counterparty_id: request.params[:id].to_i, person_id:)
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
