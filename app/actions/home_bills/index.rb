# frozen_string_literal: true

module Tally
  module Actions
    module HomeBills
      # The bills, and the new bill form, filled in when it comes from a subscription.
      class Index < Tally::Action
        def handle(request, response)
          params = request.params
          response[:prefill] = {
            payee_key: params[:payee].to_s[Tally::TransactionFilter::PAYEE], name: params[:name].to_s[0, 200],
            expected: params[:amount].to_s[/\A[\d.,]{1,20}\z/], due_day: params[:day].to_s[/\A\d{1,2}\z/]
          }
        end
      end
    end
  end
end
