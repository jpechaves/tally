# frozen_string_literal: true

module Tally
  # Picks a category for a transaction (docs/statement-import.md, section 6). Pure: it
  # gets the rules and categories as plain data and returns a decision, so the same rows
  # always get the same answer.
  #
  # The first step that matches wins:
  #
  # 1. A transfer gets no category: it is never spending or income.
  # 2. The counterparty's default category.
  # 3. Rules, lowest priority first (then oldest first).
  # 4. The bank's own category (Itaú), as a suggestion: source "bank".
  # 5. Nothing: the row waits in the review list.
  #
  # A category only applies to rows of its kind: income categories to money in (kind
  # income), expense categories to everything else. So a counterparty that pays your
  # salary and also sells you lunch can't put the lunch under Salário.
  class Categorizer
    Decision = Data.define(:category_id, :source, :rule_id) do
      def self.none = new(category_id: nil, source: "none", rule_id: nil)
    end

    class Rule
      FIELDS = %i[id field operator pattern amount_min_cents amount_max_cents category_id].freeze
      attr_reader(*FIELDS)

      def initialize(attributes)
        FIELDS.each { instance_variable_set(:"@#{_1}", attributes[_1]) }
        @matcher = (operator == "regex") ? Categorizer.regex(pattern) : Categories.fold(pattern)
      end

      # @param row [Hash] see Categorizer#call
      def match?(row)
        return false if amount_min_cents && row[:amount_cents] < amount_min_cents
        return false if amount_max_cents && row[:amount_cents] > amount_max_cents

        values(row).any? { matches?(_1) }
      end

      private

      # A description rule looks at both the cleaned and the raw description.
      def values(row)
        case field
        when "description" then [row[:description], row[:raw_description]]
        else [row[field.to_sym]]
        end.compact.map { Categories.fold(_1) }.uniq
      end

      def matches?(value)
        case operator
        when "equals" then value == @matcher
        when "contains" then value.include?(@matcher)
        when "starts_with" then value.start_with?(@matcher)
        when "regex" then @matcher&.match?(value)
        end
      end
    end

    # @return [Regexp, nil] nil when the pattern is not a valid regex
    def self.regex(pattern)
      Regexp.new(pattern.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, ""), Regexp::IGNORECASE)
    rescue RegexpError
      nil
    end

    # @param rules [Array<Hash>] active rules, in the order they run
    # @param categories [Hash{Integer => String}] category id => kind (expense | income)
    # @param bank_hints [Hash{String => Integer}] folded bank category => category id
    def initialize(rules:, categories:, bank_hints: {})
      @rules = rules.map { Rule.new(_1) }
      @kinds = categories
      @bank_hints = bank_hints
    end

    # @param row [Hash] kind, amount_cents, description, raw_description, bank_category,
    #   counterparty_name, counterparty_document, default_category_id
    # @return [Decision]
    def call(row)
      return Decision.none if row[:kind] == "transfer"

      if fits?(row[:default_category_id], row)
        return Decision.new(category_id: row[:default_category_id], source: "rule", rule_id: nil)
      end

      rule = @rules.find { fits?(_1.category_id, row) && _1.match?(row) }
      return Decision.new(category_id: rule.category_id, source: "rule", rule_id: rule.id) if rule

      hint = @bank_hints[Categories.fold(row[:bank_category])]
      return Decision.new(category_id: hint, source: "bank", rule_id: nil) if fits?(hint, row)

      Decision.none
    end

    private

    def fits?(category_id, row)
      kind = category_id && @kinds[category_id]
      return false unless kind

      (kind == "income") == (row[:kind] == "income")
    end
  end
end
