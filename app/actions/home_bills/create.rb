# frozen_string_literal: true

module Tally
  module Actions
    module HomeBills
      # A new home bill: a name, a due day, and optionally a category, the amount it usually
      # is and its payee (when it comes from the subscriptions page).
      class Create < Tally::Action
        include Deps["repos.home_bill_repo", "repos.category_repo"]

        def handle(request, response)
          params = request.params
          name = params[:name].to_s.strip[0, 200]
          due_day = params[:due_day].to_s[/\A\d{1,2}\z/].to_i
          expected = params[:expected].to_s.strip
          halt 422, t("errors.invalid_home_bill") if name.empty? || !due_day.between?(1, 31)

          id = home_bill_repo.create(name:, due_day:, category_id: category(params[:category_id]),
            expected_cents: expected.empty? ? nil : parse_amount(expected).cents.abs,
            payee_key: params[:payee_key].to_s[Tally::TransactionFilter::PAYEE], payee_label: params[:payee_label].to_s.strip[0, 200].then { _1 unless _1.empty? })
          response.redirect_to "/home-bills/#{id}"
        rescue Tally::Money::ParseError
          halt 422, t("errors.invalid_home_bill")
        end

        private

        def category(value)
          id = value.to_s.to_i
          id if category_repo.find(id)
        end
      end
    end
  end
end
