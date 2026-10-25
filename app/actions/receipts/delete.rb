# frozen_string_literal: true

module Tally
  module Actions
    module Receipts
      # Takes a receipt off its bill-month; the file goes too unless another one uses it.
      class Delete < Tally::Action
        include Deps["repos.home_bill_repo"]

        def handle(request, response)
          receipt = home_bill_repo.receipt(request.params[:id].to_i) || halt(404)
          home_bill_repo.delete_receipt(receipt).each { Tally::Receipts.delete(Tally::Receipts.dir, _1) }
          response.redirect_to Tally::HomeBills.path(receipt[:home_bill_id], Tally::HomeBills.span(request.params[:months]))
        end
      end
    end
  end
end
