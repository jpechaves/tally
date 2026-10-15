# frozen_string_literal: true

module Tally
  module Actions
    module Locale
      # Switches this browser's language and goes back to the page it came from.
      class Update < Tally::Action
        YEAR = 365 * 24 * 60 * 60

        def handle(request, response)
          locale = request.params[:locale].to_s
          halt 422 unless Tally::Locales::AVAILABLE.include?(locale)

          response.cookies[Tally::Locales::COOKIE] = {value: locale, path: "/", max_age: YEAR, same_site: :lax}
          response.redirect_to(local_path(request.params[:back]))
        end

        private

        # Only a path on this site, never another host.
        def local_path(path)
          path = path.to_s
          path.start_with?("/") && !path.start_with?("//") ? path : "/"
        end
      end
    end
  end
end
