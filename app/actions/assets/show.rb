# frozen_string_literal: true

module Tally
  module Actions
    module Assets
      # Serves the stylesheet and the few scripts in public/assets, so they load under the
      # Content Security Policy's 'self' sources instead of inline. There is no asset
      # pipeline (nothing to build on the Pi); the list is fixed.
      class Show < Tally::Action
        TYPES = {"app.css" => "text/css", "busy.js" => "text/javascript", "confirm.js" => "text/javascript", "fields.js" => "text/javascript", "picker.js" => "text/javascript", "plan.js" => "text/javascript",
                 "sidebar.js" => "text/javascript", "table.js" => "text/javascript", "world.svg" => "image/svg+xml"}.freeze

        def handle(request, response)
          name = request.params[:name].to_s
          type = TYPES[name] or halt 404

          response.headers["Content-Type"] = "#{type}; charset=utf-8"
          # The trips map's world never changes, and is the biggest file here.
          response.headers["Cache-Control"] = (type == "image/svg+xml") ? "max-age=604800" : "no-cache"
          response.body = File.read(Hanami.app.root.join("public", "assets", name), encoding: "UTF-8")
        end
      end
    end
  end
end
