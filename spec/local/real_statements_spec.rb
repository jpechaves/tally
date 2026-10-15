# frozen_string_literal: true

# An optional check of the parsers against your own statements (docs/architecture.md,
# section 17). Keep them in data/statements/ (gitignored, never committed) with their
# original file names, or point REAL_STATEMENTS_DIR at another folder, and this runs every
# parser's checks on them. With no files (CI, anyone else), it is skipped.
dir = ENV.fetch("REAL_STATEMENTS_DIR") { File.expand_path("../../data/statements", __dir__) }
real = Dir[File.join(dir, "**", "*.{csv,CSV,pdf,PDF}")].sort

RSpec.describe "Real statements" do
  if real.empty?
    it "has nothing to check" do
      skip "no files in data/statements"
    end
  end

  real.each do |path|
    it "parses #{File.basename(path)}" do
      statement = Tally::Importers.parse(File.basename(path), File.binread(path))

      expect(statement.rows).not_to be_empty
      if statement.source == "itau_card_pdf"
        bill = statement.card_statement
        charges = statement.rows.reject { _1.kind == "transfer" }.sum { _1.amount.cents }
        expect(-charges).to eq(bill[:purchases_cents] + bill[:fees_cents])
      end
    end
  end
end
