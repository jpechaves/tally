# frozen_string_literal: true

module Tally
  # The review list (docs/statement-import.md, section 6): rows with no category, or only
  # the bank's suggestion, grouped by who was paid, biggest group first. One choice per
  # group covers all its rows, and "always" covers that payee's future rows too.
  module Review
    Group = Data.define(:key, :label, :counterparty_id, :pattern, :rows, :total_cents, :totals, :suggested_category_id) do
      def ids = rows.map { _1[:id] }

      def suggested_category_name
        return unless suggested_category_id

        rows.find { _1[:category_id] == suggested_category_id }&.fetch(:category_name)
      end
    end

    module_function

    # @param rows [Array<Hash>] from TransactionRepo#to_review
    # @return [Array<Group>]
    def groups(rows)
      rows.group_by { key(_1) }.map do |key, members|
        first = members.first
        suggestions = members.map { _1[:category_id] }.uniq
        Group.new(
          key:,
          label: first[:counterparty_name] || first[:description],
          counterparty_id: first[:counterparty_id],
          pattern: first[:counterparty_id] ? nil : pattern(first[:description]),
          rows: members,
          total_cents: members.sum { _1[:amount_cents] },
          # Per currency, for showing: a payee paid in reais and in dollars (Conta Global)
          totals: members.group_by { _1.fetch(:currency, Money::DEFAULT_CURRENCY) }
            .transform_values { |rows| rows.sum { _1[:amount_cents] } },
          suggested_category_id: suggestions.size == 1 ? suggestions.first : nil
        )
      end.sort_by { [-_1.total_cents.abs, _1.label] }
    end

    # Rows of one counterparty go together. Without one (card purchases), rows whose
    # descriptions differ only in numbers and punctuation do: "FARMACIA EXEMPLO 4021" and
    # "FARMACIA EXEMPLO 1187", or the installments "LOJA EXEMPLO 03/10" and "04/10".
    def key(row)
      return "counterparty:#{row[:counterparty_id]}" if row[:counterparty_id]

      words = words(row[:description])
      "description:#{words.empty? ? Categories.fold(row[:description]) : words.join(" ")}"
    end

    # The learned rule for a description group: the same words at the start, anything
    # but letters between them. Matched without accents and ignoring case.
    def pattern(description)
      words = words(description)
      return "^#{Regexp.escape(Categories.fold(description))}$" if words.empty?

      "^#{words.map { Regexp.escape(_1) }.join("[^a-z]+")}(?![a-z])"
    end

    def words(text) = Categories.fold(text).scan(/[a-z]+/)

    # #key for SQL, as KEY_FUNCTION(counterparty_id, description), so the transactions
    # page can show one payee's rows (Tally::TransactionFilter).
    KEY_FUNCTION = "tally_payee_key"

    # Adds KEY_FUNCTION to a new SQLite connection (config/providers/db.rb).
    def register(connection)
      connection.create_function(KEY_FUNCTION, 2) do |function, counterparty_id, description|
        function.result = key({counterparty_id:, description: description.to_s})
      end
    end
  end
end
