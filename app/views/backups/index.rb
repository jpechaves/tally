# frozen_string_literal: true

module Tally
  module Views
    module Backups
      # The Pi's database backups (Tally::Backups): the last run, its check and the copies.
      class Index < Tally::View
        expose(:dir) { Tally::Backups.dir }
        expose(:copies, decorate: false) { |dir| dir ? Tally::Backups.copies(dir) : [] }
        expose(:last_run, decorate: false) { |dir| Tally::Backups.last_run(dir) if dir }
        expose(:status) { |dir| Tally::Backups.status(dir) if dir }
        expose(:downloads_on) { Tally::DatabaseExport.allowed? }
      end
    end
  end
end
