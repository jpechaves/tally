# frozen_string_literal: true

module Tally
  module Views
    module Plans
      class Index < Tally::View
        include Deps["repos.plan_repo"]

        ERRORS = {
          "invalid_target" => "Enter how much to save each month, like 1.500,00.",
          "no_data" => "There are no rows in the last three complete months to plan from. Import your statements first."
        }.freeze

        private_expose :error_code

        expose :error_message do |error_code|
          ERRORS.fetch(error_code.to_s, error_code)
        end

        expose :plans do
          plan_repo.all
        end

        expose :active do |plans|
          plans.find { _1[:status] == "active" }
        end

        expose :start_options, decorate: false do
          today = Date.today
          [today, today.next_month].map { _1.strftime("%Y-%m") }
        end
      end
    end
  end
end
