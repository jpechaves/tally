# frozen_string_literal: true

require "rack/mock"
require "securerandom"

RSpec.describe Tally::BasicAuth do
  let(:inner) { ->(_env) { [200, {"content-type" => "text/plain"}, ["ok"]] } }

  # Generated per run, so no credential-looking literal lives in the repository.
  let(:username) { "user-#{SecureRandom.hex(4)}" }
  let(:password) { SecureRandom.hex(16) }

  def request(middleware, username: nil, password: nil)
    headers = {}
    headers["HTTP_AUTHORIZATION"] = "Basic #{["#{username}:#{password}"].pack("m0")}" if username
    Rack::MockRequest.new(middleware).get("/", headers)
  end

  context "with credentials configured" do
    subject(:middleware) { described_class.new(inner, username: username, password: password, required: true) }

    it "lets the right credentials through" do
      expect(request(middleware, username: username, password: password).status).to eq(200)
    end

    it "asks for credentials when none are given" do
      response = request(middleware)

      expect(response.status).to eq(401)
      expect(response.headers["www-authenticate"]).to eq('Basic realm="Tally"')
    end

    it "rejects a wrong password or username" do
      expect(request(middleware, username: username, password: "wrong").status).to eq(401)
      expect(request(middleware, username: "other", password: password).status).to eq(401)
    end
  end

  context "without credentials" do
    it "passes requests through when auth isn't required (development, test)" do
      middleware = described_class.new(inner, required: false)

      expect(request(middleware).status).to eq(200)
    end

    it "refuses to serve when auth is required (production)" do
      middleware = described_class.new(inner, username: "", password: "", required: true)
      response = request(middleware)

      expect(response.status).to eq(503)
      expect(response.body).to include("BASIC_AUTH_USERNAME")
    end
  end

  it "takes the credentials from the settings when none are given, a blank one counting as unset" do
    settings = Hanami.app["settings"]
    allow(settings).to receive_messages(basic_auth_username: username, basic_auth_password: "  ")
    expect(request(described_class.new(inner, required: false), username:, password: "").status).to eq(503)

    allow(settings).to receive(:basic_auth_password).and_return(password)
    middleware = described_class.new(inner, required: true)
    expect(request(middleware, username:, password:).status).to eq(200)
    expect(request(middleware).status).to eq(401)
  end

  it "refuses to serve when only one of the two settings is set" do
    middleware = described_class.new(inner, username: username, required: false)

    expect(request(middleware, username: username, password: "").status).to eq(503)
  end
end
