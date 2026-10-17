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

    STREAMING = "\\b(netflix|spotify|prime video|amazon prime|disney ?plus|hbo ?max|max\\.com|globoplay|youtube|deezer|apple\\.com/bill|itunes\\.com/bill|dl\\*google|google one)\\b|\\bdisney\\+"

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
      # Only subscription descriptors: "Apple.com/Us" or a Disney park store is a purchase.
      ["description", "regex", STREAMING, "Streaming e apps"],
      ["description", "regex", "\\b(amazon|amzn|mercado ?livre|mercadolivre|shopee|magalu|magazine luiza|aliexpress|shein)\\b", "Compras online", {priority: 110}],
      ["description", "regex", "\\b(carrefour|pao de acucar|assai|atacadao|extra mercado|sams club|dia supermercado)\\b", "Supermercado"],
      ["description", "regex", "\\b(sabesp|copasa|sanepar|cedae)\\b", "Água"],
      ["description", "regex", "\\b(enel|cemig|copel|light s\\.?a|neoenergia|cpfl|equatorial)\\b", "Energia"],
      ["description", "regex", "\\b(vivo|claro|tim s\\.?a|oi s\\.?a|net servicos)\\b", "Internet e telefone"],
      ["description", "regex", "^recarga de celular\\b", "Internet e telefone"],
      ["description", "regex", "\\b(sefaz|detran|ipva|darf|das simples|prefeitura)\\b", "Impostos e taxas"],
      ["description", "regex", "^iof\\b", "IOF", {priority: 50}],
      ["description", "regex", "\\b(mensalidade|anuidade)\\b", "Tarifas bancárias", {priority: 60}],
      ["description", "regex", "receita federal", "Restituição de IR", {amount_min_cents: 1}],
      ["kind", "equals", "fee", "Tarifas bancárias", {priority: 900}],
      # Pix to people: a masked CPF, or a Pix paid with the credit card.
      ["counterparty_document", "starts_with", "•••", PIX_TO_PEOPLE, {priority: 900, amount_max_cents: -1}],
      ["description", "regex", "^pix no credito\\b", PIX_TO_PEOPLE, {priority: 900, amount_max_cents: -1}]
    ].freeze

    # Starting rules a later version rewrote: [field, operator, old pattern] => new
    # pattern. Seeding moves a starting rule still on its old pattern to the new one, so
    # the rows it categorized follow; a rule you edited is yours and stays as it is.
    REVISED_RULES = {
      ["description", "regex", "\\b(netflix|spotify|prime video|amazon prime|disney|hbo ?max|max\\.com|globoplay|youtube|deezer|apple\\.com|dl\\*google|google one)\\b"] => STREAMING
    }.freeze

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

    # The English names of the starting categories. The Portuguese names above are the
    # keys: rules and bank hints name categories in Portuguese, and Categories.names finds
    # a category under either name. A database gets its categories in the default locale
    # once (SeedCategories); after that they are yours to rename, in any language.
    ENGLISH = {
      "Moradia" => "Housing", "Aluguel" => "Rent", "Condomínio" => "Condo fees", "Energia" => "Electricity",
      "Água" => "Water", "Gás" => "Gas", "Internet e telefone" => "Internet and phone",
      "Casa e manutenção" => "Home and repairs",
      "Alimentação" => "Food", "Supermercado" => "Groceries", "Restaurantes" => "Restaurants",
      "Delivery" => "Food delivery",
      "Transporte" => "Transport", "Combustível" => "Fuel", "Aplicativo" => "Ride apps", "Estacionamento" => "Parking",
      "Transporte público" => "Public transport", "Carro: seguro e manutenção" => "Car: insurance and upkeep",
      "Saúde" => "Health", "Plano de saúde" => "Health insurance", "Farmácia" => "Pharmacy",
      "Consultas e exames" => "Doctors and tests", "Academia" => "Gym",
      "Compras" => "Shopping", "Vestuário e beleza" => "Clothing and beauty", "Compras online" => "Online shopping",
      "Eletrônicos" => "Electronics",
      "Lazer" => "Leisure", "Viagens" => "Travel", "Entretenimento" => "Entertainment",
      "Assinaturas" => "Subscriptions", "Streaming e apps" => "Streaming and apps",
      "Educação" => "Education", "Cursos e livros" => "Courses and books",
      "Pets" => "Pets", "Pet shop e veterinário" => "Pet shop and vet",
      "Dívidas" => "Debt", "Financiamentos" => "Loans", "Juros e encargos" => "Interest and charges",
      "Tarifas" => "Fees", "Tarifas bancárias" => "Bank fees", "IOF" => "IOF",
      "Impostos" => "Taxes", "Impostos e taxas" => "Taxes and duties",
      "Transferências" => "Transfers", PIX_TO_PEOPLE => "Transfers (Pix)",
      "Receitas" => "Income", "Salário" => "Salary", "Pró-labore" => "Owner's pay",
      "Restituição de IR" => "Tax refund", "Reembolsos" => "Reimbursements", "Outros recebimentos" => "Other income"
    }.freeze

    # A starting category's name in a locale: "Supermercado" -> "Groceries" in "en".
    def self.localized(name, locale)
      locale.to_s == "en" ? ENGLISH.fetch(name) : name
    end

    # Every name a starting category may have, to find it whichever locale seeded it.
    def self.names(name) = [name, ENGLISH.fetch(name)].uniq

    PORTUGUESE = ENGLISH.invert.freeze

    # A category's name to show in a locale: a starting category's name translates,
    # whichever locale seeded it ("Groceries" -> "Supermercado" in "pt-BR"); a name you
    # typed or renamed yourself shows as it is.
    def self.display(name, locale)
      original = PORTUGUESE.fetch(name, name)
      ENGLISH.key?(original) ? localized(original, locale) : name
    end

    # The names a category shows as in any locale.
    def self.shown_as(name) = ENGLISH.key?(PORTUGUESE.fetch(name, name)) ? names(PORTUGUESE.fetch(name, name)) : [name]

    # "Água", " ÁGUA " -> "agua": what rules, hints and review groups compare.
    def self.fold(text)
      text.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").downcase.strip.squeeze(" ")
    end
  end
end
