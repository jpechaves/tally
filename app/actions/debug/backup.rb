# frozen_string_literal: true

module Tally
  module Actions
    module Debug
      # Downloads one backup copy. Like the database export, only behind the login unless a
      # setting allows it (Tally::DatabaseExport.allowed?), and only a file the folder lists.
      class Backup < Tally::Action
        def handle(request, response)
          halt 403, t("backups.downloads_off") unless Tally::DatabaseExport.allowed?

          dir = Tally::Backups.dir or halt(404)
          copy = Tally::Backups.copies(dir).find { _1.file == request.params[:file] } || halt(404)
          response.unsafe_send_file(File.join(dir, copy.file))
          response.headers.merge!("Content-Type" => "application/vnd.sqlite3",
            "Content-Disposition" => %(attachment; filename="#{copy.file}"))
        end
      end
    end
  end
end
