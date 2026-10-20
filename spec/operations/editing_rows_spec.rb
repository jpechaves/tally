# frozen_string_literal: true

require "fileutils"

# The operations behind the forms that change imported rows: a category picked in review,
# an adjustment, and marking a counterparty as yourself.
RSpec.describe "Editing imported rows", :db do
  let(:db) { Hanami.app["db.gateway"].connection }

  def op(name) = Hanami.app["operations.#{name}"]

  def category_id(name) = db[:categories].where(name:).get(:id)

  def row(text) = db[:transactions].where(Sequel.like(:raw_description, "%#{text}%")).first

  before do
    name = "NU_12345678_01JUL2026_31JUL2026.csv"
    op("import_statement").call(file_name: name, content: fixture(name))
  end

  after { FileUtils.rm_rf(Hanami.app.root.join(Hanami.app["settings"].import_storage_dir)) }

  describe "assigning a category" do
    let(:cobranca) { row("Cobrança exemplo") }

    it "needs rows and a category in use" do
      expect(op("assign_category").call(ids: [], category_id: category_id("Lazer")).failure).to eq(:no_rows)
      expect(op("assign_category").call(ids: [cobranca[:id]], category_id: 999_999).failure).to eq(:category_not_found)
    end

    it "learns a description rule once, pointing it at the latest choice" do
      assign = ->(name) { op("assign_category").call(ids: [cobranca[:id]], category_id: category_id(name), always: true, pattern: "^cobranca exemplo") }

      expect(assign.call("Lazer").value!).to eq(1)
      expect(assign.call("Assinaturas").value!).to eq(1)

      rules = db[:category_rules].where(pattern: "^cobranca exemplo")
      expect(rules.select_map([:origin, :category_id, :priority])).to eq([["learned", category_id("Assinaturas"), 50]])
      expect(row("Cobrança exemplo")).to include(category_id: category_id("Assinaturas"), category_source: "rule")
    end

    it "refuses a pattern that isn't a valid regex" do
      result = op("assign_category").call(ids: [cobranca[:id]], category_id: category_id("Lazer"), always: true, pattern: "(")

      expect(result.failure).to eq(:invalid_pattern)
      expect(row("Cobrança exemplo")[:category_source]).not_to eq("manual")
    end
  end

  describe "adjusting a row" do
    def adjust(text, **attributes) = op("adjust_transaction").call(id: row(text)[:id], **attributes)

    def money(cents) = Tally::Money.new(cents)

    it "keeps a changed amount with the row's own sign" do
      adjust("iFood", kind: "amount_changed", amount: money(4_000))
      adjust("ANA EXEMPLO", kind: "amount_changed", amount: money(25_000))

      expect(db[:transaction_adjustments].select_map([:transaction_id, :amount_cents]))
        .to contain_exactly([row("iFood")[:id], -4_000], [row("ANA EXEMPLO")[:id], 25_000])
    end

    it "keeps a note trimmed, and none when it is blank" do
      adjust("iFood", kind: "canceled", note: "  pedido cancelado ")
      adjust("ANA EXEMPLO", kind: "canceled", note: "   ")

      expect(db[:transaction_adjustments].select_map([:transaction_id, :note]))
        .to contain_exactly([row("iFood")[:id], "pedido cancelado"], [row("ANA EXEMPLO")[:id], nil])
    end

    it "refuses what it can't adjust" do
      expect(op("adjust_transaction").call(id: 999_999, kind: "canceled").failure).to eq(:not_found)
      expect(adjust("Aplicação RDB", kind: "canceled").failure).to eq(:not_adjustable)
      expect(adjust("iFood", kind: "forgotten").failure).to eq(:invalid_adjustment)
      expect(adjust("iFood", kind: "amount_changed").failure).to eq(:invalid_adjusted_amount)
      expect(adjust("iFood", kind: "amount_changed", amount: money(0)).failure).to eq(:invalid_adjusted_amount)
      expect(adjust("ANA EXEMPLO", kind: "reimbursed", amount: money(100)).failure).to eq(:not_reimbursable)
      expect(adjust("iFood", kind: "reimbursed", refund_id: row("ANA EXEMPLO")[:id]).failure).to eq(:invalid_refund)
      expect(adjust("iFood", kind: "reimbursed", amount: money(4_591)).failure).to eq(:invalid_reimbursed_amount)
      expect(adjust("iFood", kind: "reimbursed").failure).to eq(:invalid_reimbursed_amount)
      expect(db[:transaction_adjustments].count).to eq(0)
    end
  end

  describe "marking a counterparty as yourself" do
    def party(name) = db[:counterparties].where(name:).get(:id)

    it "turns its rows into transfers and back into what the statement said" do
      ana = party("ANA EXEMPLO")

      op("mark_self").call(counterparty_id: ana, person_id: me_id)
      expect(row("ANA EXEMPLO")).to include(kind: "transfer", counter_account_id: nil)

      op("mark_self").call(counterparty_id: ana, person_id: nil)
      expect(row("ANA EXEMPLO")).to include(kind: "income", counter_account_id: nil)
    end

    it "leaves purchases and income alone when the counterparty isn't you" do
      ana = party("ANA EXEMPLO")

      op("mark_self").call(counterparty_id: ana, person_id: nil)
      expect(row("ANA EXEMPLO")).to include(kind: "income", counter_account_id: nil)
    end

    it "leaves a Pix no Crédito leg a transfer within its account" do
      leg = row("SECRETARIA EXEMPLO")
      expect(leg).to include(kind: "transfer", counter_account_id: leg[:account_id])

      op("mark_self").call(counterparty_id: party("SECRETARIA EXEMPLO"), person_id: nil)
      expect(row("SECRETARIA EXEMPLO")).to include(kind: "transfer", counter_account_id: leg[:account_id])
    end

    it "needs a counterparty that exists" do
      expect(op("mark_self").call(counterparty_id: 999_999, person_id: me_id).failure).to eq(:not_found)
    end
  end
end
