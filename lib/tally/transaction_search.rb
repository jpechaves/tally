# frozen_string_literal: true

module Tally
  # What a search in the transactions list (Tally::TransactionFilter#q) matches: rows whose
  # amount is the search, as imported or as adjusted, of either sign unless one is typed;
  # or whose texts (theirs, their adjustment's note, their counterparty's names and note)
  # hold every word of it. A search that is neither matches nothing.
  module TransactionSearch
    TRANSACTIONS = Sequel[:transactions]

    module_function

    # @param dataset [Sequel::Dataset] the transactions
    # @return a condition for Sequel's #where
    def condition(query, dataset)
      sign, cents = Search.amount(query)
      words = Search.fold(query).split
      conditions = []
      conditions << {TRANSACTIONS[:id] => amount_ids(dataset, sign, cents)} if cents
      conditions << Sequel.&(*words.map { word_condition(dataset.db, _1) }) unless words.empty?
      conditions.empty? ? false : Sequel.|(*conditions)
    end

    def amount_ids(dataset, sign, cents)
      amount = TRANSACTIONS[:amount_cents]
      scope = Adjustments.join(dataset.unordered)
        .where(Sequel.|({Sequel.function(:abs, amount) => cents}, {Sequel.function(:abs, Adjustments.counted_amount) => cents}))
      scope = scope.where(sign.negative? ? (amount < 0) : (amount > 0)) if sign
      scope.select(TRANSACTIONS[:id])
    end

    def word_condition(db, word)
      like = ->(table, columns) { Sequel.|(*columns.map { Search.like(Sequel[table][_1], word) }) }
      Sequel.|(
        like.call(:transactions, %i[description raw_description memo]),
        {TRANSACTIONS[:counterparty_id] => db[:counterparties].where(like.call(:counterparties, %i[name display_name note])).select(:id)},
        {TRANSACTIONS[:id] => db[:transaction_adjustments].where(like.call(:transaction_adjustments, %i[note])).select(:transaction_id)}
      )
    end
    private_class_method :amount_ids, :word_condition
  end
end
