# frozen_string_literal: true

module Tally
  # Finding a name the way you would type it: without accents, ignoring case, and with any
  # run of spaces or punctuation as one space ("joao silva" finds "JOÃO  DA-SILVA" only as
  # "joao da silva"; "joao" or "silva" find it too).
  #
  # SQLite's own LIKE folds ASCII case only, so the database gets FUNCTION, which folds a
  # column the same way the query is folded here.
  module Search
    FUNCTION = "tally_fold"

    module_function

    # "João  da-Silva" -> "JOAO DA SILVA"
    def fold(text)
      text&.unicode_normalize(:nfkd)&.gsub(/\p{Mn}/, "")&.upcase&.gsub(/[^A-Z0-9]+/, " ")&.strip
    end

    # Adds FUNCTION to a new SQLite connection (config/providers/db.rb).
    def register(connection)
      connection.create_function(FUNCTION, 1) { |function, text| function.result = fold(text) }
    end
  end
end
