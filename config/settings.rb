# frozen_string_literal: true

module Tally
  class Settings < Hanami::Settings
    # HTTP basic auth for the whole app (it runs on the home network only).
    # Optional in development and test; the app refuses to serve in production without them.
    # Set them in `.env.local` or the service environment, never in a committed file.
    setting :basic_auth_username, default: nil, constructor: Types::String.optional
    setting :basic_auth_password, default: nil, constructor: Types::String.optional
  end
end
