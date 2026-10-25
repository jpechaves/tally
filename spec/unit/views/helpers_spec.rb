# frozen_string_literal: true

# The formatting helpers every page uses (app/views/helpers.rb), through a real view scope.
RSpec.describe Tally::Views::Helpers do
  let(:i18n) { Hanami.app["i18n"] }

  subject(:helpers) do
    view = Hanami.app["views.accounts.index"]
    view.rendering(context: view.config.default_context).scope({})
  end

  around do |example|
    previous = i18n.locale
    i18n.locale = :en
    example.run
  ensure
    i18n.locale = previous
  end

  def gap(kind, from, to) = Tally::StatementGaps::Gap.new(kind:, from: Date.iso8601(from), to: Date.iso8601(to))

  def suggestion(signal, **facts) = Tally::Cuts::Suggestion.new(key: "k", signal:, facts:, monthly_cents: 0, ids: [])

  it "writes short amounts for chart axes, in thousands and millions" do
    expect([0, 29_950, 150_000, 123_456, 1_250_000_00, -300_000_000, 1_000_000_00, 100_000, 99_999, 90_000_000].map { helpers.money_compact(_1) })
      .to eq(["R$ 0", "R$ 300", "R$ 1.5K", "R$ 1.2K", "R$ 1.3M", "-R$ 3M", "R$ 1M", "R$ 1K", "R$ 1000", "R$ 900K"])
    expect(helpers.money_compact(30_000, "USD")).to eq("US$ 300")

    i18n.locale = :"pt-BR"
    expect(helpers.money_compact(150_000)).to eq("R$ 1,5 mil")
  end

  it "leaves out a date or time that isn't there" do
    expect([helpers.date(nil), helpers.timestamp(nil), helpers.timestamp("")]).to eq(["", "", ""])
    expect(helpers.timestamp("2026-09-02T22:08:12.123Z")).to eq("Sep 2, 2026 19:08")
  end

  it "names the statements and bills missing between imports" do
    expect(helpers.gap_label(gap("bill", "2026-06-01", "2026-06-01"))).to eq("missing the bill due in Jun 2026")
    expect(helpers.gap_label(gap("bill", "2026-06-01", "2026-08-01"))).to eq("missing the bills due from Jun 2026 to Aug 2026")
    expect(helpers.gap_label(gap("statement", "2026-06-01", "2026-06-30"))).to eq("missing the Jun 2026 statement")
    expect(helpers.gap_label(gap("statement", "2026-06-10", "2026-06-10"))).to eq("missing the statement for Jun 10, 2026")
    expect(helpers.gap_label(gap("statement", "2026-06-10", "2026-07-02")))
      .to eq("missing the statement from Jun 10, 2026 to Jul 2, 2026")
  end

  it "labels the filters that have no form field" do
    purchase = Struct.new(:description, :account_name).new("LOJA EXEMPLO", "Nubank cartão")

    expect(helpers.carried_filter_label(:payee, "description:loja", payee: "Loja", purchase: nil)).to eq("Loja")
    expect(helpers.carried_filter_label(:person, 7, payee: nil, purchase: nil, person: "Bruno")).to eq("Bruno")
    expect(helpers.carried_filter_label(:person, 7, payee: nil, purchase: nil)).to eq(7)
    expect(helpers.carried_filter_label(:purchase, "abc", payee: nil, purchase:)).to eq("LOJA EXEMPLO (Nubank cartão)")
    expect(helpers.carried_filter_label(:purchase, "abc", payee: nil, purchase: nil)).to eq("abc")
    expect(helpers.carried_filter_label(:month, "2026-09", payee: nil, purchase: nil)).to be_nil
  end

  it "words each cut suggestion from its facts" do
    growth = suggestion("growth", name: "Delivery", cents: 60_000, average_cents: 40_000, pct: 50, from: "2026-06", to: "2026-08")
    recurring = suggestion("recurring", payee: "Delivery", cents: 12_990, months: 3, window: 4)
    installments = suggestion("installments", count: 2, cents: 111_000, later_cents: 531_000, biggest: ["Hotel (6×)", "Doceria (2×)"])
    big = suggestion("big", name: "Delivery", count: 1, cents: 50_000, share: 20.5, pct: 50)

    expect(helpers.cut_text(growth, :title)).to eq("Food delivery: R$ 600.00, up from R$ 400.00 a month")
    expect(helpers.cut_text(growth, :detail)).to eq("50% over the average of Jun 2026 to Aug 2026.")
    # A payee keeps its own name, even one that looks like a category.
    expect(helpers.cut_text(recurring, :title)).to eq("Delivery: R$ 129.90 a month")
    expect(helpers.cut_text(installments, :detail)).to eq("Commits R$ 5,310.00 more to the next bills. Biggest: Hotel (6×), Doceria (2×).")
    expect(helpers.cut_text(big, :detail)).to eq("20.5% of the month. Cutting it by 50% saves this much.")
  end

  it "labels a source, kind or status it has no translation for by its code" do
    expect([helpers.source_label("ofx"), helpers.kind_label("gift"), helpers.status_label("imports", "odd")])
      .to eq(%w[ofx gift odd])
  end

  it "knows a row dated after today is upcoming" do
    allow(Date).to receive(:today).and_return(Date.new(2026, 9, 15))

    expect([helpers.upcoming?({occurred_on: "2026-09-16"}), helpers.upcoming?({occurred_on: "2026-09-15"})]).to eq([true, false])
  end

  it "names the page a link came from, for the breadcrumb back to it" do
    groceries = {id: 7, name: "Supermercado"}
    expect(helpers.back_label("/")).to eq("Home")
    expect(helpers.back_label("/review?page=2")).to eq("Review")
    expect(helpers.back_label("/accounts/3/report")).to eq("Account report")
    expect(helpers.back_label("/elsewhere/3")).to eq("Back")
    expect(helpers.back_label("/transactions?page=3")).to eq("Transactions")
    expect(helpers.back_label("/transactions?q=padaria&category=none&month=2026-09", [groceries])).to eq("Transactions (“padaria”, No category, Sep 2026)")
    expect(helpers.back_label("/transactions?category=7", [groceries])).to eq("Transactions (Groceries)")
    expect(helpers.back_label("/transactions?category=%zz")).to eq("Transactions")
  end
end
