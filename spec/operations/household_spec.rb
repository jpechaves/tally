# frozen_string_literal: true

require "fileutils"

# A second person's statements (issue #21): their accounts are theirs, and a Pix between
# two people of the household is a transfer, paired across both people's accounts.
RSpec.describe "A household of two", :db do
  let(:db) { Hanami.app["db.gateway"].connection }
  let(:people) { Hanami.app["repos.person_repo"] }
  let(:mark) { Hanami.app["operations.mark_self"] }
  let(:me) { people.first }
  let(:bruno) { people.create("Bruno") }

  after { FileUtils.rm_rf(Hanami.app.root.join(Hanami.app["settings"].import_storage_dir)) }

  def import(name, person_id: nil)
    Hanami.app["operations.import_statement"].call(file_name: name, content: fixture(name), person_id:)
  end

  def party(name) = db[:counterparties].where(name:).get(:id)

  def account(name) = db[:accounts].where(name:).first

  def pix(account_name, cents) = db[:transactions].where(account_id: account(account_name)[:id], amount_cents: cents).first

  def unmatched = Hanami.app["repos.transaction_repo"].list(Tally::TransactionFilter.new(kind: "unmatched"))

  it "keeps each person's accounts apart, named after their owner" do
    import("NU_12345678_01JUL2026_31JUL2026.csv")
    import("NU_87654321_01JUL2026_31JUL2026.csv", person_id: bruno.id)

    expect(account("Nubank conta")).to include(person_id: me.id, template: "Nubank conta")
    expect(account("Nubank conta (Bruno)")).to include(person_id: bruno.id, template: "Nubank conta")
    expect(db[:transactions].where(account_id: account("Nubank conta (Bruno)")[:id]).count).to eq(5)
  end

  it "pairs a Pix between the two once both are marked, and shows the one with no other side as unmatched" do
    import("NU_12345678_01JUL2026_31JUL2026.csv")
    import("NU_87654321_01JUL2026_31JUL2026.csv", person_id: bruno.id)

    mark.call(counterparty_id: party("JOSE DA SILVA EXEMPLO"), person_id: bruno.id)
    mark.call(counterparty_id: party("MARIA E SOUZA"), person_id: me.id)

    sent = pix("Nubank conta", -15_000)
    received = pix("Nubank conta (Bruno)", 15_000)
    expect(sent).to include(kind: "transfer", counter_account_id: account("Nubank conta (Bruno)")[:id])
    expect(received).to include(kind: "transfer", counter_account_id: account("Nubank conta")[:id])
    expect(sent[:transfer_id]).to eq(received[:transfer_id]).and be_truthy

    # Your own Pix to yourself at Itaú still goes to your Itaú account.
    expect(pix("Nubank conta", -150_000)).to include(kind: "transfer", counter_account_id: account("Itaú conta")[:id])
    expect(account("Itaú conta")[:person_id]).to eq(me.id)

    # Bruno paid you R$ 80, but your statement has no such Pix.
    expect(unmatched.map { _1[:amount_cents] }).to eq([-8_000])
  end

  it "pairs a Pix marked before the other person's statement came in" do
    import("NU_12345678_01JUL2026_31JUL2026.csv")
    mark.call(counterparty_id: party("JOSE DA SILVA EXEMPLO"), person_id: bruno.id)
    expect(pix("Nubank conta", -15_000)).to include(kind: "transfer", counter_account_id: nil)
    expect(unmatched.map { _1[:amount_cents] }).to eq([-15_000])

    import("NU_87654321_01JUL2026_31JUL2026.csv", person_id: bruno.id)
    mark.call(counterparty_id: party("MARIA E SOUZA"), person_id: me.id)

    expect(pix("Nubank conta", -15_000)[:transfer_id]).to be_truthy
    expect(unmatched.map { _1[:amount_cents] }).to eq([-8_000])
  end

  it "moves a counterparty from one person to another" do
    import("NU_12345678_01JUL2026_31JUL2026.csv")
    import("NU_87654321_01JUL2026_31JUL2026.csv", person_id: bruno.id)
    jose = party("JOSE DA SILVA EXEMPLO")

    mark.call(counterparty_id: jose, person_id: bruno.id)
    mark.call(counterparty_id: jose, person_id: me.id)
    expect(pix("Nubank conta", -15_000)).to include(kind: "transfer", counter_account_id: nil, transfer_id: nil)
    expect(db[:counterparties].where(id: jose).first).to include(is_self: 1, person_id: me.id)

    expect(mark.call(counterparty_id: jose, person_id: 999).failure).to eq(:not_found)
  end

  describe Tally::Repos::PersonRepo do
    it "starts with you, and adds people by a name no one else has" do
      expect(people.all.map(&:name)).to eq(["Eu"])
      expect(people.household?).to be(false)

      expect(bruno.name).to eq("Bruno")
      expect(people.create("  ")).to be_nil
      expect(people.create(" Bruno ")).to be_nil
      expect(people.all.map(&:name)).to eq(%w[Eu Bruno])
      expect(people.household?).to be(true)
    end

    it "renames a person and the accounts named after them" do
      import("NU_87654321_01JUL2026_31JUL2026.csv", person_id: bruno.id)

      expect(people.rename(bruno.id, "Beto")).to be(true)
      expect(account("Nubank conta (Beto)")).to be_truthy
      expect(people.rename(me.id, "Ana")).to be(true)
      expect(people.find(me.id).name).to eq("Ana")
      expect(account("Nubank conta (Beto)")).to be_truthy

      expect(people.rename(bruno.id, "Ana")).to be(false)
      expect(people.rename(bruno.id, "")).to be(false)
    end
  end
end
