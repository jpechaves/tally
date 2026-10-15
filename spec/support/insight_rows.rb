# frozen_string_literal: true

# Made-up rows shaped like InsightRepo#rows, for the report and cut suggestion specs.
module InsightRows
  def insight_row(occurred_on, amount, description, **attributes)
    @insight_id = (@insight_id || 0) + 1
    {
      id: @insight_id, account_id: 1, account_name: "Nubank cartão", occurred_on:,
      amount_cents: (amount * 100).round, kind: amount.negative? ? "purchase" : "income", description:,
      counterparty_id: nil, counterparty_name: nil, category_id: nil, category_name: nil, parent_id: nil,
      parent_name: nil, nature: nil, max_cut_pct: nil, installment_number: nil, installment_total: nil,
      purchase_key: nil
    }.merge(attributes)
  end

  CATEGORIES = {
    delivery: {category_id: 11, category_name: "Delivery", parent_id: 1, parent_name: "Alimentação", nature: "discretionary", max_cut_pct: 50},
    market: {category_id: 12, category_name: "Supermercado", parent_id: 1, parent_name: "Alimentação", nature: "essential", max_cut_pct: 15},
    energy: {category_id: 21, category_name: "Energia", parent_id: 2, parent_name: "Moradia", nature: "fixed", max_cut_pct: 0},
    gym: {category_id: 31, category_name: "Academia", parent_id: 3, parent_name: "Saúde", nature: "discretionary", max_cut_pct: 50},
    parking: {category_id: 41, category_name: "Estacionamento", parent_id: 4, parent_name: "Transporte", nature: "discretionary", max_cut_pct: 50},
    financing: {category_id: 51, category_name: "Financiamentos", parent_id: 5, parent_name: "Dívidas", nature: "fixed", max_cut_pct: 0}
  }.freeze

  def in_category(name) = CATEGORIES.fetch(name)
end

RSpec.configure do |config|
  config.include InsightRows
end
