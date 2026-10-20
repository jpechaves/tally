# frozen_string_literal: true

namespace :tally do
  desc "Import statement files from disk: rake 'tally:import[data/statements/*.csv]' (globs and several files work)"
  task :import, [:pattern] => :environment do |_task, args|
    paths = Dir[args[:pattern].to_s].sort
    abort "no files match #{args[:pattern].inspect}" if paths.empty?

    import_statement = Hanami.app["operations.import_statement"]
    import_repo = Hanami.app["repos.import_repo"]
    paths.each do |path|
      result = import_statement.call(file_name: File.basename(path), content: File.binread(path))
      import = result.value_or { result.failure }
      line = "#{File.basename(path)}: #{import.status.tr("_", " ")}"
      if import.status == "applied"
        line += " (#{import.rows_inserted} new, #{import.rows_updated} updated, " \
          "#{import.rows_unchanged} unchanged, #{import.rows_missing} missing)"
      end
      line += ": #{import_repo.error(import)}" if import.error
      puts line
      import_repo.warnings(import).each { puts "  warning: #{_1}" }
    end
  end
end
