# frozen_string_literal: true

module Tally
  module Actions
    module Locale
      # Switches this browser's language and goes back to the page it came from.
      class Update < Tally::Action
        def handle(request, response)
          locale = request.params[:locale].to_s
          halt 422 unless Tally::Locales::AVAILABLE.include?(locale)

          remember(response, Tally::Locales::COOKIE, locale)
          response.redirect_to(back_param(request.params[:back]) || "/")
        end
      end
    end
  end
end
