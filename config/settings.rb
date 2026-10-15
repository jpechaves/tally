# frozen_string_literal: true

module Tally
  class Settings < Hanami::Settings
    # HTTP basic auth for the whole app (it runs on the home network only).
    # Optional in development and test; the app refuses to serve in production without them.
    # Set them in `.env.local` or the service environment, never in a committed file.
    setting :basic_auth_username, default: nil, constructor: Types::String.optional
    setting :basic_auth_password, default: nil, constructor: Types::String.optional

    # Where imported statement files are kept, named by their SHA-256, so any import can be
    # audited or re-run. Relative paths are under the app root. Keep it out of git.
    setting :import_storage_dir, default: "storage/imports", constructor: Types::String

    # The Itaú account only passes money from the Pix to the card bill, so its balance
    # should stay near zero; above this many cents (either way) the app shows a warning.
    setting :pass_through_tolerance_cents, default: 5_000, constructor: Types::Params::Integer
  end
end
