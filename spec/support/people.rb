# frozen_string_literal: true

# The household's people (issue #21): you are the first one.
module People
  def me_id = Hanami.app["repos.person_repo"].first.id
end

RSpec.configure do |config|
  config.include People
end
