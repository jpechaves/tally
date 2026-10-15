# frozen_string_literal: true

module Tally
  module Views
    module Counterparties
      class Index < Tally::View
        include Deps["repos.counterparty_repo"]

        expose :counterparties do
          counterparty_repo.with_totals
        end
      end
    end
  end
end
