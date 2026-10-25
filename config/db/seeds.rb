# frozen_string_literal: true

# Loaded by `hanami db seed` and `hanami db prepare`. Safe to run any time.
#
# The generic categories and rules (lib/tally/categories.rb):
Hanami.app["operations.seed_categories"].call

# The starting travel words of trip suggestions, when there are none:
Hanami.app["repos.travel_word_repo"].seed

# Your own rules (your employer, utilities, people you pay) never go in the repository.
# Put them in data/seeds.rb, which is gitignored, and they load here too.
local = File.expand_path("../../data/seeds.rb", __dir__)
load local if File.exist?(local)

# Rows follow the rules as they are now, including a starting rule seeding just
# rewrote; manual categories stay.
Hanami.app["operations.categorize"].call
