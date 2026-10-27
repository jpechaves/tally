# frozen_string_literal: true

require "sqlite3"

RSpec.describe Tally::SqlFunction do
  let(:connection) { SQLite3::Database.new(":memory:") }
  let(:calls) { [] }

  before do
    described_class.define(connection, "shout", 2, limit: 2) do |text, mark|
      calls << text
      "#{text&.upcase}#{mark}"
    end
  end

  def shout(text) = connection.get_first_value("SELECT shout(?, '!')", [text])

  it "answers with the block's result, working it out once for the same arguments" do
    expect([shout("oi"), shout("oi"), shout(nil)]).to eq(["OI!", "OI!", "!"])
    expect(calls).to eq(["oi", nil])
  end

  it "forgets what it worked out once it holds more than the limit" do
    %w[a b c a].each { shout(_1) }

    expect(calls).to eq(%w[a b c a])
  end
end
