# frozen_string_literal: true

require "tzinfo"

module Tally
  class Settings < Hanami::Settings
    # Optional HTTP basic auth for the whole app. With both blank there is no login, in any
    # environment (production logs a warning); with only one set the app answers 503.
    # Set them in `.env.local` or the service environment, never in a committed file.
    setting :basic_auth_username, default: nil, constructor: Types::String.optional
    setting :basic_auth_password, default: nil, constructor: Types::String.optional

    # The database download on the Debug info page needs the login above, because the file
    # holds every transaction. True lets it work without one (e.g. on a trusted home network).
    setting :allow_export_without_login, default: false, constructor: Types::Params::Bool

    # Where imported statement files are kept, named by their SHA-256, so any import can be
    # audited or re-run. Relative paths are under the app root. Keep it out of git.
    setting :import_storage_dir, default: "storage/imports", constructor: Types::String

    # Where receipts of home bills are kept (Tally::Receipts), named by their SHA-256. Back it
    # up with the database; bin/reset-db leaves it alone. Keep it out of git.
    setting :receipt_storage_dir, default: "storage/receipts", constructor: Types::String

    # The Itaú account only passes money from the Pix to the card bill, so its balance
    # should stay near zero; above this many cents (either way) the app shows a warning.
    # The language the app starts in: "pt-BR" or "en" (Tally::Locales). Each browser can
    # switch with the link in the menu. New databases get their starting categories named
    # in this language too.
    setting :default_locale, default: "pt-BR", constructor: Types::String.enum("pt-BR", "en")

    setting :pass_through_tolerance_cents, default: 5_000, constructor: Types::Params::Integer

    # The time zone times are shown in (the database keeps them in UTC), by its IANA name.
    setting :time_zone, default: "America/Sao_Paulo", constructor: ->(name) { TZInfo::Timezone.get(name.to_s) }
  end
end
