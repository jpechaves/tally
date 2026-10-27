# auto_register: false
# frozen_string_literal: true

module Tally
  module Views
    class Context < Hanami::View::Context
      # What one page works out once however many partials ask, by name and the object it
      # was worked out from: the category picker's options on every row of a table (#174).
      def remember(name, object)
        remembered = ((@remembered ||= {})[name] ||= {}.compare_by_identity)
        remembered.fetch(object) { remembered[object] = yield }
      end
    end
  end
end
