# frozen_string_literal: true

module Tally
  module Actions
    module Imports
      # Receives one or more statement files from the upload form and imports each one.
      class Create < Tally::Action
        include Deps["routes", "operations.import_statement"]

        def handle(request, response)
          uploads = Array(request.params[:files]).select { _1.is_a?(Hash) && _1[:tempfile] }
          if uploads.empty?
            response.redirect_to routes.path(:imports)
            # simplecov:disable line — redirect_to halts the action, so this is never reached
            return
            # simplecov:enable line
          end

          imports = uploads.map do |upload|
            result = import_statement.(file_name: upload[:filename].to_s, content: upload[:tempfile].read)
            result.value_or { result.failure }
          end

          response.redirect_to(imports.one? ? routes.path(:import, id: imports.first.id) : routes.path(:imports))
        end
      end
    end
  end
end
