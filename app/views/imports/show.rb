# frozen_string_literal: true

module Tally
  module Views
    module Imports
      class Show < Tally::View
        include Deps["repos.import_repo", "repos.account_repo", "repos.transaction_repo"]

        expose :import

        expose :account do |import|
          import.account_id && account_repo.find(import.account_id)
        end

        expose :warnings do |import|
          import_repo.warnings(import)
        end

        expose :missing do |import|
          import.rows_missing.positive? ? transaction_repo.list(import_id: import.id, missing: true) : []
        end

        expose :rows do |import|
          import.status == "applied" ? transaction_repo.list(import_id: import.id, limit: 1000) : []
        end
      end
    end
  end
end
