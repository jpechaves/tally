# frozen_string_literal: true

require "fileutils"

RSpec.describe "Creating and accepting a savings plan", :db do
  let(:db) { Hanami.app["db.gateway"].connection }
  let(:today) { Date.new(2026, 8, 15) }

  def op(name) = Hanami.app["operations.#{name}"]

  def draft = op("create_plan").call(target_cents: 100_000, starts_month: "2026-09", today:).value!

  before do
    name = "NU_12345678_01JUL2026_31JUL2026.csv"
    op("import_statement").call(file_name: name, content: fixture(name))
  end

  after { FileUtils.rm_rf(Hanami.app.root.join(Hanami.app["settings"].import_storage_dir)) }

  it "needs a positive whole target and months with rows" do
    expect(op("create_plan").call(target_cents: 0, starts_month: "2026-09", today:).failure).to eq(:invalid_target)
    expect(op("create_plan").call(target_cents: 1_000.0, starts_month: "2026-09", today:).failure).to eq(:invalid_target)
    expect(op("create_plan").call(target_cents: 1_000, starts_month: "2026-09", today: Date.new(2030, 1, 1)).failure).to eq(:no_data)
  end

  it "accepts a draft once, with whole, non-negative limits for its own categories only" do
    id = draft
    line = db[:savings_plan_lines].where(savings_plan_id: id).first

    expect(op("accept_plan").call(id: 999_999).failure).to eq(:not_found)
    expect(op("accept_plan").call(id:, proposed: {line[:category_id] => -1}).failure).to eq(:invalid_amount)
    expect(op("accept_plan").call(id:, proposed: {line[:category_id] => 10.5}).failure).to eq(:invalid_amount)

    expect(op("accept_plan").call(id:, proposed: {line[:category_id] => 0, 999_999 => 500}).value!).to include(id:)
    expect(db[:budgets].where(category_id: line[:category_id]).get(:amount_cents)).to eq(0)
    expect(db[:budgets].where(category_id: 999_999)).to be_empty
    expect(op("accept_plan").call(id:).failure).to eq(:not_a_draft)
  end
end
