# auto_register: false
# frozen_string_literal: true

require "hanami/action"
require "dry/monads"

module Tally
  class Action < Hanami::Action
    # Provide `Success` and `Failure` for pattern matching on operation results
    include Dry::Monads[:result]

    # Every request speaks the browser's chosen language (the locale cookie), or the
    # default one. The locale is per thread, so it's set again on each request.
    before :set_locale

    private

    # A refused request (halt with a 4xx status) is a page of the app, not bare text: the
    # reason given to halt, or a translated one, in red (Views::Refusal).
    def finish(request, response, halted)
      status, text = halted
      if status && (400..499).cover?(status)
        response.status = status
        response.render(Hanami.app["views.refusal"], message: refusal_text(status, text),
          back: back_param(request.referer.to_s.sub(%r{\Ahttps?://[^/]+}, "")) || "/")
        halted = nil
      end
      super
    end

    def refusal_text(status, text)
      return text unless text == Hanami::Http::Status.message_for(status)

      (status == 404) ? t("errors.not_found") : t("errors.refused")
    end

    def set_locale(request, _response)
      i18n.locale = Tally::Locales.pick(request.cookies[Tally::Locales::COOKIE], default: Hanami.app["settings"].default_locale)
    end

    # A page of this app to go back to, from a param ("/review?page=2"), or nil. Only a
    # local path, so a link can't send you to another site.
    def back_param(value) = value.to_s[%r{\A/(?![/\\])[^\s]{0,500}\z}]

    # +path+ with a query of the +params+ that are set: "/transactions/5?back=%2Freview".
    def path_with(path, **params)
      params = params.compact
      params.empty? ? path : "#{path}?#{URI.encode_www_form(params)}"
    end

    # A "YYYY-MM" month from a param, or nil.
    def month_param(value) = value.to_s[Tally::Insights::MONTH]

    # Reads an amount typed in a form, with the current locale's decimal mark.
    def parse_amount(text)
      Tally::Money.parse(text.to_s, decimal: Tally::Money.decimal_mark(i18n.locale))
    end
  end
end
