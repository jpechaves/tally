# frozen_string_literal: true

module Tally
  module Views
    module Imports
      class Index < Tally::View
        include Deps["repos.import_repo", "repos.account_repo"]

        expose :imports do
          import_repo.recent
        end

        expose :account_names do
          account_repo.all.to_h { [_1.id, _1.name] }
        end
      end
    end
  end
end
