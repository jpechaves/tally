# frozen_string_literal: true

module Tally
  module Views
    module Plans
      class Index < Tally::View
        include Deps["repos.plan_repo"]

        # The error the last form sent back, if any (config/i18n, "errors").
        expose :error_code, decorate: false
        # What the last action did, if it says (config/i18n, "plans.index.notices").
        expose :notice_code, decorate: false

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
