# frozen_string_literal: true

# Words and merchant names that mark a row as travel, for the suggestions on a trip's page
# (issue #165). Edited on the trips page; bin/reset-db copies them back. Matched as whole
# words, ignoring case and accents, against a row's description and counterparty.
ROM::SQL.migration do
  up do
    create_table :travel_words, strict: true do
      primary_key :id
      column :word, :text, null: false, unique: true
    end
    from(:travel_words).import([:word], %w[Decolar Booking Airbnb LATAM Gol Azul Alamo Hertz Hotel].zip)
  end

  down do
    drop_table :travel_words
  end
end
