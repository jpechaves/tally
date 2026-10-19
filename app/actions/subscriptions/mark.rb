# frozen_string_literal: true

module Tally
  module Actions
    module Subscriptions
      # Says a payee is ("marked") or isn't ("dismissed") a subscription, from the
      # subscriptions page or a counterparty's page.
      class Mark < Tally::Action
        include Deps["routes", "repos.subscription_repo"]

        def handle(request, response)
          key = request.params[:key].to_s[Tally::TransactionFilter::PAYEE]
          kind = request.params[:kind].to_s
          halt 422, t("errors.missing_key") unless key && Repos::SubscriptionRepo::KINDS.include?(kind)

          subscription_repo.mark(key:, kind:, title: request.params[:title].to_s.strip[0, 300])
          response.redirect_to back_param(request.params[:back]) || routes.path(:subscriptions)
        end
      end
    end
  end
end
