# frozen_string_literal: true

module Tally
  # The languages Tally speaks (docs/architecture.md, section 12, milestone 6). Text lives
  # in config/i18n; amounts follow the locale's decimal mark (Money.decimal_mark).
  module Locales
    AVAILABLE = %w[pt-BR en].freeze

    # Each language in its own words, for the switcher.
    NAMES = {"pt-BR" => "Português", "en" => "English"}.freeze

    # The cookie that remembers a browser's choice.
    COOKIE = "locale"

    module_function

    # `value` if it's a locale Tally speaks, else `default`.
    def pick(value, default:) = AVAILABLE.include?(value.to_s) ? value.to_s : default
  end
end
