# frozen_string_literal: true

require "tmpdir"

module Tally
  module Actions
    module Debug
      # Downloads a checked copy of the database (Tally::DatabaseExport). It holds every
      # transaction, so only behind the login unless a setting allows it (DatabaseExport.allowed?).
      class Export < Tally::Action
        include Deps["db.gateway"]

        def handle(_request, response)
          halt 403, t("debug.show.export_off") unless Tally::DatabaseExport.allowed?

          Dir.mktmpdir("tally-export") do |dir|
            now = Hanami.app["settings"].time_zone.to_local(Time.now)
            path = Tally::DatabaseExport.write(gateway.connection, dir, now:)
            response.body = File.binread(path)
            response.headers.merge!("Content-Type" => "application/vnd.sqlite3",
              "Content-Disposition" => %(attachment; filename="#{File.basename(path)}"))
          end
        end
      end
    end
  end
end
