# frozen_string_literal: true

module Tally
  # The categories and rules every install starts with (docs/statement-import.md,
  # section 6). Only generic, public merchants live here: rules for your own employer,
  # utilities, gym or people stay in your local database (the repository is public).
  module Categories
    # How far the savings planner may cut a category, by nature (architecture.md, 8.1).
    MAX_CUT_PCT = {"fixed" => 0, "essential" => 15, "discretionary" => 50}.freeze
    NATURES = MAX_CUT_PCT.keys.freeze

    PIX_TO_PEOPLE = "Transferências (Pix)"

    # parent => {category => nature}. Category names are unique, so rules and bank hints
    # can name them directly.
    EXPENSES = {
      "Moradia" => {
        "Aluguel" => "fixed", "Condomínio" => "fixed", "Energia" => "fixed", "Água" => "fixed",
        "Gás" => "essential", "Internet e telefone" => "fixed", "Casa e manutenção" => "discretionary"
      },
      "Alimentação" => {"Supermercado" => "essential", "Restaurantes" => "discretionary", "Delivery" => "discretionary"},
      "Transporte" => {
        "Combustível" => "essential", "Aplicativo" => "discretionary", "Estacionamento" => "discretionary",
        "Transporte público" => "essential", "Carro: seguro e manutenção" => "fixed"
      },
      "Saúde" => {
        "Plano de saúde" => "fixed", "Farmácia" => "essential", "Consultas e exames" => "essential",
        "Academia" => "discretionary"
      },
      "Compras" => {"Vestuário e beleza" => "discretionary", "Compras online" => "discretionary", "Eletrônicos" => "discretionary"},
      "Lazer" => {"Viagens" => "discretionary", "Entretenimento" => "discretionary"},
      "Assinaturas" => {"Streaming e apps" => "discretionary"},
      "Educação" => {"Cursos e livros" => "essential"},
      "Pets" => {"Pet shop e veterinário" => "essential"},
      "Dívidas" => {"Financiamentos" => "fixed", "Juros e encargos" => "fixed"},
      "Tarifas" => {"Tarifas bancárias" => "fixed", "IOF" => "fixed"},
      "Impostos" => {"Impostos e taxas" => "fixed"},
      "Transferências" => {PIX_TO_PEOPLE => "essential"}
    }.freeze

    INCOME = {
      "Receitas" => ["Salário", "Pró-labore", "Restituição de IR", "Reembolsos", "Outros recebimentos"]
    }.freeze

    # [field, operator, pattern, category, options]. Regexes are matched without accents
    # and ignoring case, so write them without accents. Lower priority runs first; the
    # catch-alls at 900 run after everything else.
    RULES = [
      ["description", "regex", "\\bifood\\b", "Delivery"],
      ["description", "regex", "\\b(rappi|ze delivery)\\b", "Delivery"],
      ["description", "regex", "\\b(uber|99 ?(app|pop|tecnologia)|cabify)\\b", "Aplicativo"],
      ["description", "regex", "\\b(posto|shell|ipiranga|petrobras|br mania)\\b", "Combustível"],
      ["description", "regex", "\\b(estacionamento|estapar|parking|zul\\+|sem parar|conectcar|veloe)\\b", "Estacionamento"],
      ["description", "regex", "\\b(drogasil|droga ?raia|raia drogasil|pague menos|drogaria|panvel)\\b", "Farmácia"],
      ["description", "regex", "\\b(petz|petlove|cobasi)\\b", "Pet shop e veterinário"],
      ["description", "regex", "\\b(latam|gol linhas|voegol|azul linhas|voeazul|airbnb|booking\\.com|decolar)\\b", "Viagens"],
      ["description", "regex", "\\b(netflix|spotify|prime video|amazon prime|disney|hbo ?max|max\\.com|globoplay|youtube|deezer|apple\\.com|dl\\*google|google one)\\b", "Streaming e apps"],
      ["description", "regex", "\\b(amazon|amzn|mercado ?livre|mercadolivre|shopee|magalu|magazine luiza|aliexpress|shein)\\b", "Compras online", {priority: 110}],
      ["description", "regex", "\\b(carrefour|pao de acucar|assai|atacadao|extra mercado|sams club|dia supermercado)\\b", "Supermercado"],
      ["description", "regex", "\\b(sabesp|copasa|sanepar|cedae)\\b", "Água"],
      ["description", "regex", "\\b(enel|cemig|copel|light s\\.?a|neoenergia|cpfl|equatorial)\\b", "Energia"],
      ["description", "regex", "\\b(vivo|claro|tim s\\.?a|oi s\\.?a|net servicos)\\b", "Internet e telefone"],
      ["description", "regex", "\\b(sefaz|detran|ipva|darf|das simples|prefeitura)\\b", "Impostos e taxas"],
      ["description", "regex", "^iof\\b", "IOF", {priority: 50}],
      ["description", "regex", "\\b(mensalidade|anuidade)\\b", "Tarifas bancárias", {priority: 60}],
      ["description", "regex", "receita federal", "Restituição de IR", {amount_min_cents: 1}],
      ["kind", "equals", "fee", "Tarifas bancárias", {priority: 900}],
      # Pix to people: a masked CPF, or a Pix paid with the credit card.
      ["counterparty_document", "starts_with", "•••", PIX_TO_PEOPLE, {priority: 900, amount_max_cents: -1}],
      ["description", "regex", "^pix no credito\\b", PIX_TO_PEOPLE, {priority: 900, amount_max_cents: -1}]
    ].freeze

    # Itaú prints its own category under each card row. It only suggests a category
    # (category_source "bank"), shown as such in the review list. Keys are folded:
    # no accents, lower case.
    BANK_HINTS = {
      "supermercado" => "Supermercado",
      "supermarket" => "Supermercado",
      "restaurante" => "Restaurantes",
      "viagem" => "Viagens",
      "hotel" => "Viagens",
      "saude" => "Consultas e exames",
      "health" => "Consultas e exames",
      "vestuario" => "Vestuário e beleza",
      "educacao" => "Cursos e livros",
      "lazer" => "Entretenimento",
      "casa" => "Casa e manutenção",
      "eletronicos" => "Eletrônicos",
      "automovel" => "Carro: seguro e manutenção",
      "automobile" => "Carro: seguro e manutenção"
    }.freeze

    # "Água", " ÁGUA " -> "agua": what rules, hints and review groups compare.
    def self.fold(text)
      text.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").downcase.strip.squeeze(" ")
    end
  end
end
