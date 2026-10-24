# frozen_string_literal: true

require "digest"
require "rack/auth/basic"
require "rack/utils"

module Tally
  # HTTP basic auth in front of the whole app.
  #
  # Credentials come from the basic_auth_username / basic_auth_password settings, unless
  # given explicitly. It's an optional layer: with both blank, requests pass through in every
  # environment (something else, like a VPN or Cloudflare Access, may guard the app), and
  # production logs a warning at boot so an open app is never silent. Only one of the two
  # set is a mistake, so the app answers 503 until both are.
  class BasicAuth
    REALM = "Tally"
    OFF_WARNING = "basic auth is off: both BASIC_AUTH_* are empty"

    # Whether the settings turn the login on (both credentials set), for the pages that only
    # work behind it, like the database export.
    def self.on?(settings = Hanami.app["settings"])
      [settings.basic_auth_username, settings.basic_auth_password].none? { |value| value.to_s.strip.empty? }
    end

    def initialize(app, username: nil, password: nil, production: Hanami.env?(:production), logger: nil)
      @app = app
      @explicit = [username, password] if username || password
      (logger || Hanami.app["logger"]).warn(OFF_WARNING) if production && off?
    end

    def call(env)
      return @app.call(env) if off?

      username, password = credentials
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

    def off?
      credentials.all? { |value| blank?(value) }
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
