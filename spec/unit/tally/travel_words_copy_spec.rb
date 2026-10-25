# frozen_string_literal: true

require "tmpdir"

RSpec.describe Tally::TravelWordsCopy do
  around { |example| Dir.mktmpdir { |dir| @dir = dir and example.run } }

  def database(name, sql)
    path = File.join(@dir, name)
    SQLite3::Database.new(path) { _1.execute_batch(sql) }
    path
  end

  let(:table) { "CREATE TABLE travel_words (id integer PRIMARY KEY, word text NOT NULL UNIQUE);" }

  it "replaces the starting words with yours, and keeps them from a database from before the list" do
    new = database("new.sqlite", "#{table} INSERT INTO travel_words (word) VALUES ('Decolar'), ('Hotel');")
    expect(described_class.call(from: database("older.sqlite", "CREATE TABLE accounts (id integer);"), to: new)).to be_nil

    old = database("old.sqlite", "#{table} INSERT INTO travel_words (id, word) VALUES (3, 'Hotel'), (12, 'Agência Exemplo');")
    expect(described_class.call(from: old, to: new)).to eq(2)
    SQLite3::Database.new(new) { expect(_1.execute("SELECT id, word FROM travel_words ORDER BY id")).to eq([[3, "Hotel"], [12, "Agência Exemplo"]]) }
  end
end
