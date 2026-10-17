# frozen_string_literal: true

require "fileutils"

RSpec.describe "Categorization", :db do
  let(:db) { Hanami.app["db.gateway"].connection }
  let(:storage) { Hanami.app.root.join(Hanami.app["settings"].import_storage_dir) }

  after { FileUtils.rm_rf(storage) }

  def op(name) = Hanami.app["operations.#{name}"]

  def import(name) = op("import_statement").(file_name: name, content: fixture(name))

  def category_id(name) = db[:categories].where(name:).get(:id)

  # The row with this description, as printed or cleaned.
  def row(text, amount_cents = nil)
    scope = db[:transactions].where(Sequel.|({raw_description: text}, {description: text}))
    scope = scope.where(amount_cents:) if amount_cents
    scope.first
  end

  def category_of(text, amount_cents = nil)
    found = row(text, amount_cents)
    [db[:categories].where(id: found[:category_id]).get(:name), found[:category_source]]
  end

  describe "seeding" do
    it "adds the categories and rules once, with nature and maximum cut" do
      expect(op("seed_categories").().value!).to eq(categories: 52, rules: Tally::Categories::RULES.size)
      expect(op("seed_categories").().value!).to eq(categories: 0, rules: 0)

      expect(db[:categories].where(name: "Delivery").first).to include(kind: "expense", nature: "discretionary", max_cut_pct: 50)
      expect(db[:categories].where(name: "Supermercado").first).to include(nature: "essential", max_cut_pct: 15)
      expect(db[:categories].where(name: "Energia").first).to include(nature: "fixed", max_cut_pct: 0)
      expect(db[:categories].where(name: "Salário").first).to include(kind: "income", nature: nil)
      expect(db[:categories].where(name: "Moradia").get(:parent_id)).to be_nil
    end

    it "never changes what you edited, nor brings back a rule you removed" do
      op("seed_categories").()
      db[:categories].where(name: "Delivery").update(nature: "essential", max_cut_pct: 10)
      rule = db[:category_rules].where(pattern: "\\bifood\\b").get(:id)
      op("disable_rule").(id: rule)

      op("seed_categories").()

      expect(db[:categories].where(name: "Delivery").first).to include(nature: "essential", max_cut_pct: 10)
      expect(db[:category_rules].where(pattern: "\\bifood\\b").count).to eq(1)
      expect(db[:category_rules].where(id: rule).get(:disabled_at)).not_to be_nil
    end

    it "moves a starting rule a later version rewrote, keeping its rows' manual categories" do
      op("seed_categories").()
      (field, operator, old), pattern = Tally::Categories::REVISED_RULES.first
      rule = db[:category_rules].where(field:, operator:, pattern:).get(:id)
      db[:category_rules].where(id: rule).update(pattern: old)
      account = db[:accounts].insert(name: "Nubank cartão", kind: "credit_card")
      store, bill, manual = [["Apple.Com/Us", -800_000], ["Apple.Com/Bill", -1_990], ["Apple.Com/Us", -300_000]]
        .each_with_index.map do |(description, amount_cents), index|
          db[:transactions].insert(account_id: account, occurred_on: "2026-09-0#{index + 1}", amount_cents:,
            kind: "purchase", description:, raw_description: description, external_id: "x#{index}")
        end
      op("categorize").()
      db[:transactions].where(id: manual).update(category_id: category_id("Eletrônicos"), category_source: "manual")
      expect(db[:transactions].where(id: store).get(:category_rule_id)).to eq(rule)

      op("seed_categories").()
      op("categorize").()

      expect(db[:category_rules].where(id: rule).get(:pattern)).to eq(pattern)
      expect(db[:category_rules].where(field:, operator:, pattern:).count).to eq(1)
      expect(db[:transactions].where(id: store).get(:category_id)).to be_nil
      expect(db[:transactions].where(id: bill).get(:category_id)).to eq(category_id("Streaming e apps"))
      expect(db[:transactions].where(id: manual).get(:category_id)).to eq(category_id("Eletrônicos"))
    end

    it "leaves a starting rule you edited as it is" do
      op("seed_categories").()
      (field, operator, _), pattern = Tally::Categories::REVISED_RULES.first
      rule = db[:category_rules].where(field:, operator:, pattern:).get(:id)
      db[:category_rules].where(id: rule).update(pattern: "apple\\.com\\b")

      op("seed_categories").()

      expect(db[:category_rules].where(id: rule).get(:pattern)).to eq("apple\\.com\\b")
    end

    it "names them in English for an English install, and never adds them twice across languages" do
      expect(op("seed_categories").(locale: "en").value!).to eq(categories: 52, rules: Tally::Categories::RULES.size)
      expect(db[:categories].where(name: "Groceries").first).to include(nature: "essential", max_cut_pct: 15)
      expect(db[:categories].where(id: db[:categories].where(name: "Food delivery").get(:parent_id)).get(:name)).to eq("Food")
      expect(db[:categories].where(name: "Supermercado").count).to eq(0)
      expect(db[:category_rules].where(pattern: "\\bifood\\b").get(:category_id)).to eq(category_id("Food delivery"))

      expect(op("seed_categories").(locale: "pt-BR").value!).to eq(categories: 0, rules: 0)
    end

    it "suggests the bank's category under its English name too" do
      op("seed_categories").(locale: "en")
      import("itau_2026-10.pdf")

      expect(category_of("MERCADO EXEMPLOSAO PAUL")).to eq(["Groceries", "bank"])
    end
  end

  describe "on import" do
    before do
      import("NU_12345678_01JUL2026_31JUL2026.csv")
      import("Nubank_2026-07-09.csv")
      import("itau_2026-10.pdf")
    end

    it "seeds the categories the first time" do
      expect(db[:categories].count).to eq(52)
    end

    it "uses the rules, then the bank's category as a suggestion" do
      expect(category_of("Compra no débito via NuPay - iFood")).to eq(["Delivery", "rule"])
      expect(category_of("iFood - NuPay", 2150)).to eq(["Delivery", "rule"])
      expect(category_of("IOF de \"Streaming Exemplo* Sub\"")).to eq(["IOF", "rule"])
      expect(category_of("POSTO EXEMPLO")).to eq(["Combustível", "rule"])
      expect(category_of("MERCADO EXEMPLOSAO PAUL")).to eq(["Supermercado", "bank"])
      expect(category_of("PET EXEMPLO*PETL")).to eq([nil, "none"])
    end

    it "puts Pix to people under Transferências (Pix), and leaves transfers alone" do
      expect(category_of("JOSE DA SILVA EXEMPLO")).to eq(["Transferências (Pix)", "rule"])
      expect(category_of("Pix no Crédito - JOAO EXEMPLO - 1/3")).to eq(["Transferências (Pix)", "rule"])
      expect(category_of("Pagamento de fatura")).to eq([nil, "none"])
      expect(db[:transactions].where(kind: "transfer").exclude(category_id: nil).count).to eq(0)
    end

    it "counts each rule's rows" do
      expect(db[:category_rules].where(pattern: "\\bifood\\b").get(:hits)).to eq(3)
    end

    it "takes a Pix to yourself out of Transferências (Pix) when you say it's you" do
      me = db[:counterparties].where(name: "MARIA E SOUZA").get(:id)
      expect(category_of("MARIA E SOUZA")).to eq(["Transferências (Pix)", "rule"])

      op("mark_self").(counterparty_id: me, is_self: true)

      expect(category_of("MARIA E SOUZA")).to eq([nil, "none"])
    end

    it "keeps a category you picked through re-imports and rule changes" do
      op("assign_category").(ids: [row("iFood - NuPay", -4780)[:id]], category_id: category_id("Restaurantes"))

      # Different bytes, same rows: applied again, every row upserted.
      result = op("import_statement").(file_name: "Nubank_2026-07-09.csv", content: "#{fixture("Nubank_2026-07-09.csv")}\n")
      expect(result.value!).to have_attributes(status: "applied", rows_unchanged: 14)
      op("categorize").()

      expect(category_of("iFood - NuPay", -4780)).to eq(["Restaurantes", "manual"])
      expect(category_of("iFood - NuPay", 2150)).to eq(["Delivery", "rule"])
    end
  end

  describe "choosing in the review list" do
    before do
      import("NU_12345678_01JUL2026_31JUL2026.csv")
      import("itau_2026-10.pdf")
    end

    it "with always, makes it the counterparty's default for its other rows" do
      energy = db[:counterparties].where(name: "ENERGIA EXEMPLO S.A.").get(:id)
      ids = db[:transactions].where(counterparty_id: energy).select_map(:id)

      result = op("assign_category").(ids:, category_id: category_id("Energia"), always: true, counterparty_id: energy)

      expect(result).to be_success
      expect(db[:counterparties].where(id: energy).get(:default_category_id)).to eq(category_id("Energia"))
      expect(category_of("ENERGIA EXEMPLO S.A.")).to eq(["Energia", "rule"])
    end

    it "with always and no counterparty, learns a rule that covers the next bills too" do
      pattern = Tally::Review.pattern("PET EXEMPLO*PETL")
      op("assign_category").(ids: [row("PET EXEMPLO*PETL")[:id]], category_id: category_id("Pet shop e veterinário"),
        always: true, pattern:)

      rule = db[:category_rules].where(origin: "learned").first
      expect(rule).to include(field: "description", operator: "regex", pattern:, hits: 1)
      expect(category_of("PET EXEMPLO*PETL")).to eq(["Pet shop e veterinário", "rule"])

      # The same payee on a later bill.
      later = row("PET EXEMPLO*PETL").merge(id: nil, external_id: "later", raw_description: "PET EXEMPLO*PETL 2",
        category_id: nil, category_source: "none", category_rule_id: nil)
      new_id = db[:transactions].insert(later.except(:id))
      op("categorize").(ids: [new_id])
      expect(category_of("PET EXEMPLO*PETL 2")).to eq(["Pet shop e veterinário", "rule"])
    end

    it "without always, sets only those rows, by hand" do
      ids = db[:transactions].where(raw_description: "ESTACIONAMENTO EXEMPLO").select_map(:id)
      op("assign_category").(ids: ids.first(1), category_id: category_id("Lazer"))

      expect(db[:transactions].where(id: ids).order(:id).select_map(:category_source)).to eq(%w[manual rule])
      expect(db[:category_rules].where(origin: "learned").count).to eq(0)
    end

    it "still applies your pick to rows the default can't cover" do
      company = db[:counterparties].where(name: "EMPRESA EXEMPLO LTDA").get(:id)
      ids = db[:transactions].where(counterparty_id: company).select_map(:id)

      # An expense category for money in: the default can't apply, the rows still get it.
      op("assign_category").(ids:, category_id: category_id("Lazer"), always: true, counterparty_id: company)

      expect(category_of("EMPRESA EXEMPLO LTDA")).to eq(["Lazer", "manual"])
    end

    it "refuses an unknown or archived category" do
      expect(op("assign_category").(ids: [1], category_id: 999_999).failure).to eq(:category_not_found)
    end
  end

  describe "rules and categories you change" do
    before { import("itau_2026-10.pdf") }

    it "re-categorizes past rows when you add or remove a rule" do
      result = op("save_rule").(field: "bank_category", operator: "equals", pattern: "Outros",
        category_id: category_id("Compras online"), priority: 200)
      expect(result).to be_success
      expect(category_of("PET EXEMPLO*PETL")).to eq(["Compras online", "rule"])

      op("disable_rule").(id: result.value!)
      expect(category_of("PET EXEMPLO*PETL")).to eq([nil, "none"])
    end

    it "refuses a broken regex" do
      result = op("save_rule").(field: "description", operator: "regex", pattern: "(oops", category_id: category_id("Lazer"))

      expect(result.failure).to eq(:invalid_pattern)
    end

    it "sends rows back to review when their category is archived" do
      op("save_category").(id: category_id("Combustível"), name: "Combustível", nature: "essential", archived: true)

      expect(category_of("POSTO EXEMPLO")).to eq([nil, "none"])
    end

    it "adds a category under a parent, taking its kind and the nature's maximum cut" do
      result = op("save_category").(name: "Cuidador", parent_id: category_id("Saúde"), nature: "essential")

      expect(db[:categories].where(id: result.value!).first).to include(kind: "expense", max_cut_pct: 15)
      expect(op("save_category").(name: "Cuidador", parent_id: category_id("Saúde")).failure).to eq(:name_taken)
      expect(op("save_category").(name: "X", parent_id: category_id("Cuidador")).failure).to eq(:invalid_parent)
    end
  end
end
