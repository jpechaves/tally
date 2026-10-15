# frozen_string_literal: true

module Tally
  module Actions
    module Scripts
      # Serves the few scripts in public/scripts, so they run under the Content Security
      # Policy's script-src 'self' instead of inline.
      class Show < Tally::Action
        NAMES = %w[plan].freeze

        def handle(request, response)
          name = request.params[:name].to_s
          halt 404 unless NAMES.include?(name)

          response.headers["Content-Type"] = "text/javascript; charset=utf-8"
          response.headers["Cache-Control"] = "no-cache"
          response.body = File.read(Hanami.app.root.join("public", "scripts", "#{name}.js"), encoding: "UTF-8")
        end
      end
    end
  end
end
