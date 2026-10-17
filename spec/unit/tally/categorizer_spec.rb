# frozen_string_literal: true

RSpec.describe Tally::Categorizer do
  let(:food) { 1 }
  let(:delivery) { 2 }
  let(:salary) { 3 }
  let(:pix) { 4 }
  let(:categories) { {food => "expense", delivery => "expense", salary => "income", pix => "expense"} }
  let(:rules) do
    [
      {id: 10, field: "description", operator: "regex", pattern: "\\bifood\\b", category_id: delivery},
      {id: 11, field: "description", operator: "contains", pattern: "Padaria São", category_id: food},
      {id: 12, field: "counterparty_document", operator: "equals", pattern: "12.345.678/0001-90", category_id: salary},
      {id: 13, field: "counterparty_document", operator: "starts_with", pattern: "•••", category_id: pix,
       amount_max_cents: -1}
    ]
  end
  let(:categorizer) { described_class.new(rules:, categories:, bank_hints: {"supermercado" => food}) }

  def row(**attributes)
    {kind: "purchase", amount_cents: -1000, description: "X", raw_description: "X"}.merge(attributes)
  end

  def decide(**attributes) = categorizer.(row(**attributes)).to_h

  it "never categorizes a transfer" do
    expect(decide(kind: "transfer", description: "iFood")).to eq(category_id: nil, source: "none", rule_id: nil)
  end

  it "uses the counterparty's default before any rule" do
    expect(decide(description: "iFood", default_category_id: food)).to eq(category_id: food, source: "rule", rule_id: nil)
  end

  it "applies the first rule that matches, in order" do
    expect(decide(description: "iFood - NuPay")).to eq(category_id: delivery, source: "rule", rule_id: 10)
  end

  it "compares text without accents and ignoring case" do
    expect(decide(description: "PADARIA SAO JORGE")).to include(category_id: food, rule_id: 11)
    expect(decide(description: "IFOOD *RESTAURANTE")).to include(category_id: delivery)
  end

  it "matches description rules on the raw description too" do
    expect(decide(description: "Restaurante", raw_description: "Compra no débito via NuPay - iFood"))
      .to include(category_id: delivery)
  end

  it "doesn't match a word inside another word" do
    expect(decide(description: "LIFOODS LTDA")).to include(source: "none")
  end

  it "keeps income categories for money in, and expense categories for the rest" do
    expect(decide(kind: "income", amount_cents: 500_000, counterparty_document: "12.345.678/0001-90"))
      .to include(category_id: salary)
    expect(decide(counterparty_document: "12.345.678/0001-90")).to include(source: "none")
    expect(decide(kind: "income", amount_cents: 2000, description: "iFood")).to include(source: "none")
  end

  it "checks the amount range" do
    expect(decide(counterparty_document: "•••.123.456-••")).to include(category_id: pix, rule_id: 13)
    expect(decide(kind: "refund", amount_cents: 1000, counterparty_document: "•••.123.456-••")).to include(source: "none")
  end

  it "falls back to the bank's category as a suggestion" do
    expect(decide(bank_category: "SUPERMERCADO")).to eq(category_id: food, source: "bank", rule_id: nil)
  end

  it "ignores rules pointing at categories it doesn't know (archived)" do
    categorizer = described_class.new(rules:, categories: categories.except(delivery))

    expect(categorizer.(row(description: "iFood")).source).to eq("none")
  end

  it "skips a rule with a broken regex instead of failing" do
    broken = {id: 1, field: "description", operator: "regex", pattern: "(unclosed", category_id: food}
    categorizer = described_class.new(rules: [broken] + rules, categories:)

    expect(categorizer.(row(description: "iFood")).rule_id).to eq(10)
  end

  it "matches every seed rule against the merchants it names" do
    names = Tally::Categories::RULES.map { _1[3] }.uniq
    ids = names.each_with_index.to_h { |name, index| [name, index + 1] }
    seed_rules = Tally::Categories::RULES.each_with_index.map do |(field, operator, pattern, category, options), id|
      {id:, field:, operator:, pattern:, category_id: ids.fetch(category), **(options || {})}
        .then { |rule| rule.merge(priority: rule.fetch(:priority, 100)) }
    end.sort_by { [_1[:priority], _1[:id]] }
    categorizer = described_class.new(rules: seed_rules, categories: ids.values.to_h { [_1, "expense"] }.merge(ids["Restituição de IR"] => "income"))
    category = ->(**attributes) { ids.key(categorizer.(row(**attributes)).category_id) }

    expect(category.(description: "UBER *TRIP")).to eq("Aplicativo")
    expect(category.(description: "99 TECNOLOGIA LTDA")).to eq("Aplicativo")
    expect(category.(description: "POSTO EXEMPLO")).to eq("Combustível")
    expect(category.(description: "DROGASIL 1234")).to eq("Farmácia")
    expect(category.(description: "NETFLIX.COM")).to eq("Streaming e apps")
    expect(category.(description: "AMAZON PRIME CANAIS")).to eq("Streaming e apps")
    expect(category.(description: "Apple.Com/Bill", amount_cents: -1_990)).to eq("Streaming e apps")
    expect(category.(description: "Apple.Com/Us", amount_cents: -800_000)).to be_nil
    expect(category.(description: "DISNEY PLUS")).to eq("Streaming e apps")
    expect(category.(description: "DISNEY+")).to eq("Streaming e apps")
    expect(category.(description: "DISNEY STORE EXEMPLO")).to be_nil
    expect(category.(description: "AMAZON MARKETPLACE")).to eq("Compras online")
    expect(category.(description: "MERCADOLIVRE*LOJA")).to eq("Compras online")
    expect(category.(description: "IOF de \"Streaming Exemplo\"")).to eq("IOF")
    expect(category.(kind: "fee", description: "Mensalidade - Plano do")).to eq("Tarifas bancárias")
    expect(category.(kind: "fee", description: "Juros do rotativo")).to eq("Tarifas bancárias")
    expect(category.(description: "Pix no Crédito - JOAO EXEMPLO")).to eq("Transferências (Pix)")
    expect(category.(kind: "income", amount_cents: 120_000, description: "SECR. DA RECEITA FEDERAL")).to eq("Restituição de IR")
  end
end
