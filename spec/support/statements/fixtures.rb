# frozen_string_literal: true

module StatementFixtures
  DIR = SPEC_ROOT.join("fixtures", "statements")

  def fixture_path(name) = DIR.join(name)

  def fixture(name) = File.binread(fixture_path(name))

  def parse_fixture(name) = Tally::Importers.parse(name, fixture(name))
end

RSpec.configure do |config|
  config.include StatementFixtures
end
