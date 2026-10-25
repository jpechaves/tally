# frozen_string_literal: true

require "yaml"

module Tally
  # Where a row was bought, for the trips map (issue #144, docs/architecture.md, section
  # 8.8). Itaú's card bill prints the city under each purchase (transactions.location),
  # cut at about 13 characters and spelled as it comes ("SAO PAULO", "So Paulo",
  # "RIO DE JANEIR"); Conta Global ends the merchant with it ("Loja Exemplo TORONTO");
  # Nubank has none. The cities and their coordinates are public data in
  # config/places.yml, never anything from a statement.
  class Places
    Place = Data.define(:name, :lat, :lon)

    # The places found, each once, and the text that matched none.
    Found = Data.define(:places, :missing)

    FILE = File.expand_path("../../config/places.yml", __dir__)

    # Shorter text could be the start of too many cities.
    PREFIX_MIN = 8

    # The end of a merchant's name tried as a city, longest first ("Rio de Janeiro").
    TAIL_WORDS = 3

    def self.default = @default ||= new(YAML.load_file(FILE))

    # @param entries [Array<Hash>] "name", "lat", "lon" and optional "aliases"
    def initialize(entries)
      @keys = entries.flat_map do |entry|
        place = Place.new(name: entry["name"], lat: entry["lat"], lon: entry["lon"])
        names = [entry["name"], *entry["aliases"]]
        # Statements drop the accented letters as often as their accents ("So Paulo").
        names += names.map { _1.gsub(/[^\p{ASCII}]/, "") }
        names.map { [Search.fold(_1), place] }.uniq
      end
      # A name of several cities is the biggest one's (the file is biggest first).
      @exact = @keys.uniq(&:first).to_h
    end

    def find(text)
      key = Search.fold(text)
      return if key.to_s.empty?

      @exact[key] || (@keys.find { _1.first.start_with?(key) }&.last if key.length >= PREFIX_MIN)
    end

    # @param rows [Array<Hash>] with description, location and currency
    def of(rows)
      places = []
      missing = []
      rows.each do |row|
        city = row[:location].to_s
        next if city.empty? && row[:currency] == Money::DEFAULT_CURRENCY

        place = city.empty? ? tail(row[:description]) : find(city)
        if place then places << place
        else missing << (city.empty? ? row[:description] : city)
        end
      end
      Found.new(places: places.uniq, missing: missing.uniq)
    end

    private

    def tail(description)
      words = description.split
      TAIL_WORDS.downto(1).lazy.filter_map { @exact[Search.fold(words.last(_1).join(" "))] }.first
    end
  end
end
