# frozen_string_literal: true

require "rack/test"

RSpec.shared_context "with Rack::Test" do
  # Define the app for Rack::Test requests; each request fails on an N+1 query
  # (spec/support/n_plus_one.rb).
  let(:app) { ->(env) { NPlusOne.check { Hanami.app.call(env) } } }
end

RSpec.configure do |config|
  config.include Rack::Test::Methods, type: :request
  config.include_context "with Rack::Test", type: :request

  # Pages default to Portuguese; the request specs read them in English unless they pick
  # a language themselves (spec/requests/locale_spec.rb).
  config.before(type: :request) { set_cookie "locale=en" }

  # No page may show a key it has no translation for.
  config.after(type: :request) do
    body = last_response.body
  rescue Rack::Test::Error
    nil # no request made
  else
    expect(body).not_to include("translation_missing")
  end
end
