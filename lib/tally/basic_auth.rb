# frozen_string_literal: true

require "digest"
require "rack/auth/basic"
require "rack/utils"

module Tally
  # HTTP basic auth in front of the whole app.
  #
  # Credentials come from the basic_auth_username / basic_auth_password settings, unless
  # given explicitly. Without them, requests pass through in development and test, and the
  # app answers 503 in production, so a missing setting can never leave it open.
  class BasicAuth
    REALM = "Tally"

    def initialize(app, username: nil, password: nil, required: nil)
      @app = app
      @explicit = [username, password] if username || password
      @required = required
    end

    def call(env)
      username, password = credentials

      if blank?(username) && blank?(password)
        return required? ? misconfigured("set BASIC_AUTH_USERNAME and BASIC_AUTH_PASSWORD") : @app.call(env)
      end
      return misconfigured("set both BASIC_AUTH_USERNAME and BASIC_AUTH_PASSWORD") if blank?(username) || blank?(password)

      auth = Rack::Auth::Basic::Request.new(env)
      if auth.provided? && auth.basic? && auth.credentials && valid?(auth.credentials, username, password)
        @app.call(env)
      else
        unauthorized
      end
    end

    private

    def credentials
      @explicit || begin
        settings = Hanami.app["settings"]
        [settings.basic_auth_username, settings.basic_auth_password]
      end
    end

    def required?
      @required.nil? ? Hanami.env?(:production) : @required
    end

    # Compares digests so neither the length nor the content leaks through timing.
    def valid?(given, username, password)
      given_user, given_pass = given
      user_ok = Rack::Utils.secure_compare(digest(given_user), digest(username))
      pass_ok = Rack::Utils.secure_compare(digest(given_pass), digest(password))
      user_ok & pass_ok
    end

    def digest(value)
      Digest::SHA256.hexdigest(value.to_s)
    end

    def blank?(value)
      value.nil? || value.strip.empty?
    end

    def unauthorized
      [
        401,
        {"content-type" => "text/plain", "www-authenticate" => %(Basic realm="#{REALM}")},
        ["Unauthorized\n"]
      ]
    end

    def misconfigured(hint)
      [503, {"content-type" => "text/plain"}, ["Tally is not configured: #{hint}.\n"]]
    end
  end
end
