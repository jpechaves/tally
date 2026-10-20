# frozen_string_literal: true

source "https://rubygems.org"

ruby ">= 3.3"

gem "hanami", "~> 3.0.0"
gem "hanami-action", "~> 3.0.0"
gem "hanami-db", "~> 3.0.0"
gem "hanami-router", "~> 3.0.0"
gem "hanami-view", "~> 3.0.0"

gem "bigdecimal" # money parsing; a bundled (not default) gem from Ruby 3.4
gem "csv" # statement import; a bundled (not default) gem from Ruby 3.4
gem "dry-types", "~> 1.7"
gem "dry-operation", ">= 1.0.1"
gem "dry-validation", "~> 1.11"
gem "i18n", "~> 1.14"
gem "puma", ">= 7.1"
gem "rake"
gem "sqlite3"
gem "tzinfo", "~> 2.0" # times shown in the TIME_ZONE setting, from the system zoneinfo

group :development do
  gem "hanami-webconsole", "~> 3.0.0"
end

group :development, :test do
  gem "dotenv"
  # Linter and formatter: `bundle exec standardrb` (`--fix` to autocorrect)
  gem "standard", require: false
  # Code analysis (Flay, Flog, Reek): `bundle exec rubycritic app lib`
  gem "rubycritic", require: false
  # Known advisories in Gemfile.lock: `bundle exec bundler-audit check --update`
  gem "bundler-audit", require: false
  # Syntax highlighting SQL logs
  gem "rouge"
end

group :cli, :development do
  gem "hanami-reloader", "~> 3.0.0"
end

group :cli, :development, :test do
  gem "hanami-rspec", "~> 3.0.0"
end

group :test do
  # Database
  gem "database_cleaner-sequel"

  # Web integration
  gem "capybara"
  gem "rack-test"

  # Line and branch coverage of app/ and lib/ (spec/spec_helper.rb)
  gem "simplecov", require: false
end
