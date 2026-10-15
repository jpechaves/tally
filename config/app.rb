# frozen_string_literal: true

require "hanami"
require_relative "../lib/tally/basic_auth"

module Tally
  class App < Hanami::App
    config.middleware.use Tally::BasicAuth

    # Translations live in config/i18n. Each request picks its locale (Tally::Action).
    config.i18n.default_locale = :"pt-BR"
    config.i18n.available_locales = %i[pt-BR en]
  end
end
