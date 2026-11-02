# frozen_string_literal: true

namespace :tally do
  desc "Regroup card merchants after a grouping fix (imports do this too, but skip files already imported): " \
    "rake tally:regroup_merchants"
  task regroup_merchants: :environment do
    moved = Hanami.app["repos.counterparty_repo"].link_merchants
    changed = Hanami.app["operations.categorize"].call(ids: moved).value!
    puts "#{moved.size} rows moved to another merchant, #{changed} recategorized"
  end
end
