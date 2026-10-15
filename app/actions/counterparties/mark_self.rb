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

          # Back to the same search and page.
          params = request.params
          query = {q: params[:q].to_s.strip[0, 100], page: params[:page].to_s[/\A\d{1,6}\z/]}
            .reject { |_, value| value.nil? || value.empty? }
          response.redirect_to [routes.path(:counterparties), URI.encode_www_form(query)].reject(&:empty?).join("?")
        end
      end
    end
  end
end
