# frozen_string_literal: true

RSpec.describe "Saving categories and rules", :db do
  let(:db) { Hanami.app["db.gateway"].connection }

  def op(name) = Hanami.app["operations.#{name}"]

  def category_id(name) = db[:categories].where(name:).get(:id)

  before { op("seed_categories").call }

  describe "a category" do
    def save(**attributes) = op("save_category").call(name: "Feira", **attributes)

    it "adds a top-level category of the kind asked, with its nature's maximum cut" do
      id = save(kind: "expense", nature: "discretionary").value!

      expect(db[:categories].where(id:).first).to include(name: "Feira", kind: "expense", parent_id: nil, nature: "discretionary",
        max_cut_pct: 50)
    end

    it "adds income categories without a nature" do
      id = save(kind: "income", nature: "essential").value!

      expect(db[:categories].where(id:).first).to include(kind: "income", nature: nil, max_cut_pct: nil)
    end

    it "takes the kind of its parent" do
      id = save(kind: "income", parent_id: category_id("Alimentação")).value!

      expect(db[:categories].where(id:).first).to include(kind: "expense", parent_id: category_id("Alimentação"))
    end

    it "changes one, keeping it in use unless it is archived, and lets a nature not be cut at all" do
      id = save(kind: "expense", nature: "discretionary").value!

      expect(op("save_category").call(id:, name: " Feira  livre ", nature: "essential", max_cut_pct: 0).value!).to eq(id)
      expect(db[:categories].where(id:).first).to include(name: "Feira livre", nature: "essential", max_cut_pct: 0,
        archived_at: nil)
      expect(save(kind: "expense", nature: "essential", max_cut_pct: -1).failure).to eq(:invalid_max_cut)
    end

    it "refuses what it can't save" do
      expect(op("save_category").call(name: "  ", kind: "expense").failure).to eq(:empty_name)
      expect(save(id: 999_999).failure).to eq(:not_found)
      expect(save(kind: "savings").failure).to eq(:invalid_kind)
      expect(save(kind: "expense", nature: "luxury").failure).to eq(:invalid_nature)
      expect(save(kind: "expense", nature: "essential", max_cut_pct: 101).failure).to eq(:invalid_max_cut)
      expect(save(kind: "expense", parent_id: category_id("Delivery")).failure).to eq(:invalid_parent)
      expect(op("save_category").call(name: "Delivery", kind: "expense", parent_id: category_id("Alimentação")).failure)
        .to eq(:name_taken)
    end
  end

  describe "a rule" do
    def save(**attributes)
      op("save_rule").call(field: "description", operator: "contains", pattern: "feira", category_id: category_id("Supermercado"),
        **attributes)
    end

    it "adds a manual rule" do
      id = save(priority: 7, amount_max_cents: -1).value!

      expect(db[:category_rules].where(id:).first).to include(origin: "manual", priority: 7, amount_max_cents: -1,
        pattern: "feira")
    end

    it "trims the pattern and runs after the starting rules unless given a priority" do
      id = save(pattern: "  feira livre ").value!

      expect(db[:category_rules].where(id:).first).to include(pattern: "feira livre", priority: 100)
    end

    it "refuses what it can't save" do
      expect(save(field: "memo").failure).to eq(:invalid_field)
      expect(save(operator: "ends_with").failure).to eq(:invalid_field)
      expect(save(pattern: " ").failure).to eq(:empty_pattern)
      expect(save(operator: "regex", pattern: "(").failure).to eq(:invalid_pattern)
      expect(save(category_id: 999_999).failure).to eq(:category_not_found)
    end
  end
end
