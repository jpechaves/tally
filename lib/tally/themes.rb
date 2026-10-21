# frozen_string_literal: true

module Tally
  # The looks Tally comes in (docs/design.md): Linear's dark canvas, or its light one. With
  # no choice made, the browser follows the system's setting (prefers-color-scheme).
  module Themes
    AVAILABLE = %w[dark light].freeze

    # Not a theme of its own: forgets the choice, so the browser follows the system again.
    SYSTEM = "system"

    # The cookie that remembers a browser's choice.
    COOKIE = "theme"

    module_function

    # `value` if it's a theme Tally has, else nil (the layout then follows the system).
    def pick(value) = AVAILABLE.include?(value.to_s) ? value.to_s : nil
  end
end
