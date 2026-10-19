# frozen_string_literal: true

module Tally
  module Views
    module Counterparties
      class Show < Tally::View
        expose :party
        expose :back, decorate: false
      end
    end
  end
end
