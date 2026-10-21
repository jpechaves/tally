# frozen_string_literal: true

module Tally
  module Actions
    module Receipts
      # A receipt file, only through the app (behind its login), never from public/. Files
      # never change, so browsers may keep them for a year.
      class Show < Tally::Action
        include Deps["repos.home_bill_repo"]

        def handle(request, response)
          receipt = home_bill_repo.receipt(request.params[:id].to_i) || halt(404)
          path = Tally::Receipts.path(Tally::Receipts.dir, receipt[:sha256])
          halt 404 unless File.exist?(path)

          response.unsafe_send_file(path)
          response.headers.merge!("Content-Type" => receipt[:mime], "Cache-Control" => "private, max-age=31536000, immutable",
            "X-Content-Type-Options" => "nosniff")
        end
      end
    end
  end
end
