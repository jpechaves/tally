# frozen_string_literal: true

require "tmpdir"

RSpec.describe Tally::HomeBillsCopy do
  around { |example| Dir.mktmpdir { |dir| @dir = dir and example.run } }

  let(:schema) { Hanami.app.root.join("config/db/structure.sql").read }

  def database(name, sql = schema)
    path = File.join(@dir, name)
    SQLite3::Database.new(path) { _1.execute_batch(sql) }
    path
  end

  it "copies bills, payments and receipts, finding categories again by name" do
    old = database("old.sqlite")
    SQLite3::Database.new(old) do |db|
      db.execute_batch(<<~SQL)
        INSERT INTO categories (id, name, kind) VALUES (1, 'Moradia', 'expense'), (2, 'Energia', 'expense'), (3, 'Minha categoria', 'expense');
        UPDATE categories SET parent_id = 1 WHERE id = 2;
        INSERT INTO home_bills (id, name, category_id, due_day, payee_key) VALUES (5, 'Energia', 2, 10, 'match:|ENERGIA EXEMPLO'), (6, 'Água', 3, 15, NULL);
        INSERT INTO home_bill_payments (home_bill_id, month, paid_on, amount_cents, account_name, external_id) VALUES (5, '2026-10', '2026-10-08', 18240, 'Nubank conta', 'fake-1');
        INSERT INTO home_bill_receipts (home_bill_id, month, sha256, mime, byte_size, filename) VALUES (5, '2026-10', 'abc', 'image/png', 3, 'receipt.png');
      SQL
    end
    new = database("new.sqlite")
    SQLite3::Database.new(new) { _1.execute_batch("INSERT INTO categories (id, name, kind) VALUES (7, 'Moradia', 'expense'); INSERT INTO categories (id, name, kind, parent_id) VALUES (8, 'Energia', 'expense', 7);") }

    expect(described_class.call(from: old, to: new)).to eq(2)
    SQLite3::Database.new(new) do |db|
      expect(db.execute("SELECT id, category_id, payee_key FROM home_bills ORDER BY id")).to eq([[5, 8, "match:|ENERGIA EXEMPLO"], [6, nil, nil]])
      expect(db.get_first_value("SELECT external_id FROM home_bill_payments")).to eq("fake-1")
      expect(db.get_first_value("SELECT filename FROM home_bill_receipts")).to eq("receipt.png")
    end
  end

  it "copies nothing from a database from before home bills" do
    expect(described_class.call(from: database("old.sqlite", "CREATE TABLE accounts (id integer);"), to: database("new.sqlite"))).to eq(0)
  end
end
