# auto_register: false
# frozen_string_literal: true

module Tally
  module Actions
    module Budgets
      # Sends a budgets form back to the month it was on, with the error, if any.
      module Back
        private

        def back(response, month, error = nil)
          query = {month:, error:}.compact
          path = routes.path(:budgets)
          response.redirect_to query.empty? ? path : "#{path}?#{URI.encode_www_form(query)}"
        end
      end
    end
  end
end
