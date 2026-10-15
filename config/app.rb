# frozen_string_literal: true

require "hanami"
require_relative "../lib/tally/basic_auth"

module Tally
  class App < Hanami::App
    config.middleware.use Tally::BasicAuth
  end
end
