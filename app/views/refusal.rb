# frozen_string_literal: true

module Tally
  module Views
    # A request the app refused (Tally::Action#finish): why, in red, inside the app's own
    # layout, with a link back to the page it came from.
    class Refusal < Tally::View
      expose :message, :back
    end
  end
end
