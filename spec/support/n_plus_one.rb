# frozen_string_literal: true

# Fails a request when one line of app code runs the same SELECT more than MAX_REPEATS
# times: the N+1 shape, one query per row where one query for all the rows would do.
# Bullet does this for ActiveRecord; Tally's queries go through ROM and Sequel, so this
# reads them from Sequel's logger instead. Every request spec runs through it
# (spec/support/requests.rb).
module NPlusOne
  MAX_REPEATS = 5

  # Repeats that are by design, by "file#method" of the line that runs them.
  ALLOWED = {
    # Each statement row's counterparty is matched (by name, CNPJ company or a name cut
    # short) against those earlier rows of the same file created, so it can't be looked
    # up for all rows at once.
    "app/repos/counterparty_repo.rb#upsert" => true,
    "app/repos/counterparty_repo.rb#company" => true,
    "app/repos/counterparty_repo.rb#cut_short" => true,
    "app/repos/counterparty_repo.rb#find" => true,
    # Once per uploaded file: a request can carry many statements.
    "app/repos/account_repo.rb#by_template" => true,
    # Once per account a statement creates: whose it is decides its name.
    "app/repos/person_repo.rb#first" => true,
    "app/repos/account_repo.rb#all" => true,
    "app/repos/import_repo.rb#find" => true
  }.freeze

  APP_CODE = %r{\A#{Regexp.escape(SPEC_ROOT.parent.to_s)}/((?:app|lib)/.+)}

  class Error < StandardError; end

  module_function

  # @raise [Error] naming each line that repeated a query, and how often
  def check
    @queries = []
    result = yield
    repeats = @queries.tally.select { |(site, sql), count| count > MAX_REPEATS && sql.start_with?("SELECT") && !ALLOWED[site] }
    raise Error, repeats.map { |(site, sql), count| "#{count}x #{site}: #{sql[0, 120]}..." }.join("\n") unless repeats.empty?

    result
  ensure
    @queries = nil
  end

  # Sequel's logger interface; queries log at the info level.
  def info(message)
    return unless @queries

    site = caller_locations.find { APP_CODE.match?(_1.path) }
    return unless site

    @queries << ["#{site.path[APP_CODE, 1]}##{site.base_label}", normalize(message)]
  end

  def debug(*) = nil

  def warn(*) = nil

  def error(*) = nil

  # The SQL without timing, source note or values, so one query run for different rows reads the same.
  def normalize(message)
    message.sub(/\A\(\d+\.\d+s\) (\(source: .*?'\) )?/, "")
      .gsub(/'(?:[^']|'')*'/, "?")
      .gsub(/\b\d+(\.\d+)?\b/, "?")
      .gsub(/\((?:\?, )+\?\)/, "(?)")
  end
end

RSpec.configure do |config|
  config.before(:suite) do
    Hanami.app["db.rom"].gateways.each_value { _1.connection.loggers << NPlusOne }
  end
end
