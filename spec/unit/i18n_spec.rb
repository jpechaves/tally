# frozen_string_literal: true

require "yaml"

# Both languages must say everything: the same keys, the same placeholders, and a
# translation for every code the app shows (kinds, statuses, errors, cut signals).
RSpec.describe "Translations" do
  # {"a" => {"b" => "x"}} -> {"a.b" => "x"}; plural forms ({"one", "other"}) stay one key.
  def flatten(hash, prefix = nil)
    hash.flat_map do |key, value|
      path = [prefix, key].compact.join(".")
      (value.is_a?(Hash) && !(value.key?("one") && value.key?("other"))) ? flatten(value, path).to_a : [[path, value]]
    end.to_h
  end

  def placeholders(value) = Array(value.is_a?(Hash) ? value.values : value).join(" ").scan(/%\{(\w+)\}/).flatten.uniq.sort

  # Formats and day and month names come from Hanami's English defaults in en.
  let(:skip) { /\A(date|time)\./ }
  let(:english) { flatten(YAML.load_file(Hanami.app.root.join("config/i18n/en.yml"))["en"]).reject { _1 =~ skip } }
  let(:portuguese) { flatten(YAML.load_file(Hanami.app.root.join("config/i18n/pt-BR.yml"))["pt-BR"]).reject { _1 =~ skip } }

  it "has the same keys and placeholders in both languages" do
    expect(portuguese.keys.sort).to eq(english.keys.sort)
    english.each do |key, value|
      expect([key, placeholders(portuguese[key])]).to eq([key, placeholders(value)])
    end
  end

  it "translates every key the pages and actions name" do
    used = Dir[Hanami.app.root.join("app/**/*.{rb,erb}")].flat_map { File.read(_1, encoding: "UTF-8").scan(/\bt\("([a-z_.]+)"/).flatten }.uniq
    expect(used.size).to be > 100
    expect(used - english.keys).to eq([])
  end

  it "translates every code the app shows" do
    codes = {
      "kinds" => %w[purchase refund fee income transfer bill_payment],
      "natures" => Tally::Categories::NATURES + ["unset"],
      "sources" => Tally::Importers::SOURCES.keys,
      "statuses.import" => %w[applied duplicate_file rejected],
      "statuses.account" => %w[checking credit_card investment cash],
      "statuses.plan" => %w[draft active replaced],
      "statuses.rule" => %w[seed learned manual],
      "statuses.category" => %w[expense income],
      "rules.fields" => Tally::Views::Rules::Index::FIELDS,
      "rules.operators" => Tally::Views::Rules::Index::OPERATORS,
      "accounts.index.check" => %w[ok warning unknown],
      "errors" => Dir[Hanami.app.root.join("app/operations/*.rb")].flat_map { File.read(_1, encoding: "UTF-8").scan(/Failure\(:(\w+)/).flatten }.uniq
    }
    codes.each do |prefix, values|
      values.each { expect(english).to have_key("#{prefix}.#{_1}") }
    end
    Tally::Cuts::SIGNALS.each do |signal|
      %w[name title detail].each { expect(english).to have_key("cuts.signals.#{signal}.#{_1}") }
    end
  end

  it "names every starting category in English" do
    names = Tally::Categories::EXPENSES.flat_map { |parent, children| [parent, *children.keys] } +
      Tally::Categories::INCOME.flat_map { |parent, children| [parent, *children] }
    expect(names - Tally::Categories::ENGLISH.keys).to eq([])
    english_names = names.map { Tally::Categories.localized(_1, "en") }
    expect(english_names.uniq.size).to eq(names.size)
  end

  it "shows a starting category in the current language, whichever language seeded it" do
    expect(Tally::Categories.display("Supermercado", "en")).to eq("Groceries")
    expect(Tally::Categories.display("Groceries", "pt-BR")).to eq("Supermercado")
    expect(Tally::Categories.display("Groceries", "en")).to eq("Groceries")
    expect(Tally::Categories.display("Mercadinho", "en")).to eq("Mercadinho")
    expect(Tally::Categories.shown_as("Groceries")).to eq(%w[Supermercado Groceries])
    expect(Tally::Categories.shown_as("Mercadinho")).to eq(["Mercadinho"])
  end
end
