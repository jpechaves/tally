# auto_register: false
# frozen_string_literal: true

module Tally
  module Actions
    module Trips
      # A trip's name, first and last day, and accounts, as sent by the new and edit forms.
      # "Todas as contas" is stored as no accounts; picking nothing at all is refused.
      module Form
        DATE = /\A\d{4}-\d{2}-\d{2}\z/

        private

        def trip_params(request)
          name = request.params[:name].to_s.strip[0, 200]
          starts_on, ends_on = [request.params[:starts_on], request.params[:ends_on]].map { date(_1) }
          halt 422, t("errors.invalid_trip") if name.empty? || !starts_on || !ends_on || starts_on > ends_on

          all = request.params[:all_accounts] == "1"
          account_ids = all ? [] : Array(request.params[:account_ids]).map(&:to_i) & account_repo.all.map(&:id)
          halt 422, t("errors.trip_accounts") if !all && account_ids.empty?

          {name:, starts_on:, ends_on:, account_ids:}
        end

        def date(value) = begin
          Date.iso8601(value.to_s[DATE].to_s).iso8601
        rescue
          nil
        end
      end
    end
  end
end
