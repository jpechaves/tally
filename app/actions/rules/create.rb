# frozen_string_literal: true

module Tally
  module Actions
    module Rules
      class Create < Tally::Action
        include Deps["routes", "operations.save_rule"]

        def handle(request, response)
          params = request.params
          result = save_rule.(
            field: params[:field].to_s,
            operator: params[:operator].to_s,
            pattern: params[:pattern],
            category_id: params[:category_id].to_i,
            priority: params[:priority].to_s[/\A\d+\z/]&.to_i || 100,
            amount_min_cents: cents(params[:amount_min]),
            amount_max_cents: cents(params[:amount_max])
          )

          path = routes.path(:rules)
          response.redirect_to result.failure? ? "#{path}?error=#{result.failure}" : path
        rescue Tally::Money::ParseError
          response.redirect_to "#{routes.path(:rules)}?error=invalid_amount"
        end

        private

        # "-50,00" -> -5000; blank -> nil
        def cents(text)
          text = text.to_s.strip
          text.empty? ? nil : Tally::Money.parse(text, decimal: ",").cents
        end
      end
    end
  end
end
