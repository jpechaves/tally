# frozen_string_literal: true

RSpec.describe Tally::Repos::CounterpartyRepo, :db do
  subject(:repo) { Hanami.app["repos.counterparty_repo"] }

  let(:db) { Hanami.app["db.gateway"].connection }
  let(:account) { db[:accounts].insert(name: "Nubank cartão", kind: "credit_card") }
  let(:cnpj) { {document: "00.000.000/0001-00", document_kind: "cnpj"} }

  def charge(counterparty, description = "x")
    @row = (@row || 0) + 1
    db[:transactions].insert(account_id: account, occurred_on: "2026-09-01", amount_cents: -1_000, kind: "purchase",
      description:, raw_description: description, external_id: "r#{@row}", counterparty_id: counterparty.id)
  end

  describe "#upsert" do
    it "makes a card merchant with a company's name that company" do
      company = repo.upsert(name: "TELEFONIA EXEMPLO", **cnpj)

      expect(repo.upsert(name: "TELEFONIA EXEMPLO*AB12").id).to eq(company.id)
      expect(repo.upsert(name: "Telefonia Exemplo").id).to eq(company.id)
    end

    it "keeps a card merchant apart from a person or a different name" do
      person = repo.upsert(name: "TELEFONIA EXEMPLO", document: "•••.123.456-••", document_kind: "cpf_masked")
      repo.upsert(name: "TELEFONIA EXEMPLO SERVICOS", **cnpj)

      expect(repo.upsert(name: "TELEFONIA EXEMPLO").id).not_to eq(person.id)
      expect(db[:counterparties].count).to eq(3)
    end
  end

  describe "#link_merchants" do
    it "moves a card merchant's rows to the company paid by Pix or boleto, with its default category" do
      merchant = repo.upsert(name: "TELEFONIA EXEMPLO")
      category = db[:categories].insert(name: "Telefone", kind: "expense")
      repo.set_default_category(merchant.id, category)
      rows = [charge(merchant), charge(merchant)]
      company = repo.upsert(name: "TELEFONIA EXEMPLO", **cnpj)
      other = charge(repo.upsert(name: "PADARIA EXEMPLO"))

      expect(repo.link_merchants).to match_array(rows)

      expect(db[:transactions].where(id: rows).select_map(:counterparty_id).uniq).to eq([company.id])
      expect(db[:transactions].where(id: other).get(:counterparty_id)).not_to eq(company.id)
      expect(db[:counterparties].where(id: merchant.id).count).to eq(0)
      expect(repo.find(company.id).default_category_id).to eq(category)
      expect(repo.link_merchants).to eq([])
    end

    it "keeps the company's own default category" do
      merchant = repo.upsert(name: "TELEFONIA EXEMPLO")
      company = repo.upsert(name: "TELEFONIA EXEMPLO", **cnpj)
      mine, theirs = %w[Telefone Celular].map { db[:categories].insert(name: _1, kind: "expense") }
      repo.set_default_category(merchant.id, theirs)
      repo.set_default_category(company.id, mine)

      repo.link_merchants

      expect(repo.find(company.id).default_category_id).to eq(mine)
    end
  end
end
