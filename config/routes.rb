# frozen_string_literal: true

module Tally
  class Routes < Hanami::Routes
    root to: "home.show"
  end
end
