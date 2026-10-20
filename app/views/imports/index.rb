# frozen_string_literal: true

module Tally
  module Views
    module Imports
      class Index < Tally::View
        include Deps["repos.import_repo", "repos.account_repo", "repos.person_repo"]

        expose :imports do
          import_repo.recent
        end

        expose :gaps do
          import_repo.gaps
        end

        # Whose statements these are, when the household has more than one person (issue #21).
        expose :people, decorate: false do
          person_repo.all
        end

        expose :account_names do
          account_repo.all.to_h { [_1.id, _1.name] }
        end
      end
    end
  end
end
