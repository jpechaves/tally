# frozen_string_literal: true

module Tally
  module Operations
    # Switches a rule off (seed rules stay off even when seeds run again), then
    # categorizes every row that isn't manual again.
    class DisableRule < Tally::Operation
      include Deps["repos.category_rule_repo", "operations.categorize"]

      def call(id:)
        step Failure(:not_found) unless category_rule_repo.find(id)

        transaction do
          category_rule_repo.disable(id)
          categorize.call
        end
      end
    end
  end
end
