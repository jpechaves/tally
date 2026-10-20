# frozen_string_literal: true

module Tally
  module Actions
    module Plans
      class Create < Tally::Action
        include Deps["routes", "operations.create_plan"]

        def handle(request, response)
          target = parse_amount(request.params[:target].to_s).cents
          starts = month_param(request.params[:starts_month]) || Date.today.next_month.strftime("%Y-%m")
          result = create_plan.call(target_cents: target, starts_month: starts)

          if result.failure?
            response.redirect_to "#{routes.path(:plans)}?error=#{result.failure}"
          else
            response.redirect_to routes.path(:plan, id: result.value!)
          end
        rescue Tally::Money::ParseError
          response.redirect_to "#{routes.path(:plans)}?error=invalid_target"
        end
      end
    end
  end
end
