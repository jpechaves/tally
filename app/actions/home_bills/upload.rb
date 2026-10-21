# frozen_string_literal: true

module Tally
  module Actions
    module HomeBills
      # Keeps a receipt (a photo or PDF of a boleto or Pix) for a bill's month.
      class Upload < Tally::Action
        include Deps["repos.home_bill_repo"]

        def handle(request, response)
          bill = found(home_bill_repo, request)
          month = month_param(request.params[:month])
          upload = request.params[:file]
          halt 422, t("errors.invalid_receipt") unless month && upload.is_a?(Hash) && upload[:tempfile]

          stored = Tally::Receipts.store(Tally::Receipts.dir, upload[:tempfile])
          halt 422, t("errors.invalid_receipt") unless stored.is_a?(Tally::Receipts::Stored)

          home_bill_repo.add_receipt(home_bill_id: bill[:id], month:, **stored.to_h, filename: File.basename(upload[:filename].to_s)[0, 200])
          response.redirect_to "/home-bills/#{bill[:id]}"
        end
      end
    end
  end
end
