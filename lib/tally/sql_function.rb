# frozen_string_literal: true

module Tally
  # A Ruby function SQLite can call, like Tally::Search's tally_fold, that remembers what
  # it worked out. A search or a grouping calls one for every row, often several times per
  # page, and the folding is slow on the Pi (#174); rows mostly repeat the same texts, so
  # the answer for each argument is kept until there are LIMIT of them, then all are
  # dropped and kept again from there, which bounds the memory.
  module SqlFunction
    LIMIT = 20_000

    module_function

    # @yield the function's arguments, for its result; it must depend on them alone
    def define(connection, name, arity, limit: LIMIT, &block)
      cache = {}
      connection.create_function(name, arity) do |function, *arguments|
        function.result = cache.fetch(arguments) do
          cache.clear if cache.size >= limit
          cache[arguments] = block.call(*arguments)
        end
      end
    end
  end
end
