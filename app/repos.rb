# auto_register: false
# frozen_string_literal: true

module Tally
  module Repos
    # The timestamp format every table uses: ISO-8601 UTC with milliseconds.
    def self.now = Time.now.utc.strftime("%Y-%m-%dT%H:%M:%S.%LZ")
  end
end
