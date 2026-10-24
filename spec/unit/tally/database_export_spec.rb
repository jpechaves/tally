# frozen_string_literal: true

require "tmpdir"

RSpec.describe Tally::DatabaseExport do
  let(:db) { Hanami.app["db.gateway"].connection }

  it "writes a checked copy of the database, named after the local time" do
    Dir.mktmpdir do |dir|
      path = described_class.write(db, dir, now: Time.new(2026, 10, 24, 9, 5, 7))

      expect(File.basename(path)).to eq("tally-20261024-090507.sqlite")
      Sequel.sqlite(path) { |copy| expect(copy[:categories].count).to eq(db[:categories].count) }
    end
  end

  it "refuses a copy that fails the integrity check" do
    damaged = instance_double(Sequel::Dataset, single_value: "*** in database main ***")
    allow(Sequel).to receive(:sqlite).and_yield(instance_double(Sequel::Database, fetch: damaged))

    Dir.mktmpdir do |dir|
      expect { described_class.write(db, dir) }.to raise_error(Tally::DatabaseExport::Damaged, /in database main/)
    end
  end
end
