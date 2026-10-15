# frozen_string_literal: true

module Tally
  module Views
    module Installments
      class Index < Tally::View
        include Deps["repos.insight_repo", "repos.transaction_repo"]

        expose :calendar do
          Tally::InstallmentCalendar.new(insight_repo.installment_rows, from: Date.today.strftime("%Y-%m"))
        end

        expose :bills do
          transaction_repo.card_statements_with_account
        end
      end
    end
  end
end
