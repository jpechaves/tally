# frozen_string_literal: true

module Tally
  module Actions
    module Transactions
      class Index < Tally::Action
        def handle(request, response)
          response[:account_id] = request.params[:account].to_s[/\A\d+\z/]&.to_i
          response[:month] = request.params[:month].to_s[/\A\d{4}-\d{2}\z/]
        end
      end
    end
  end
end
