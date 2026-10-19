# frozen_string_literal: true

RSpec.describe Tally::Repos::ImportRepo, :db do
  subject(:repo) { Hanami.app["repos.import_repo"] }

  let(:notice) { Tally::Importers::Notice[:zero_amount, line: 2] }

  def create(**attributes)
    repo.create(source: "test", file_name: "test.csv", file_sha256: "0" * 64, file_size: 1, status: "applied", **attributes)
  end

  it "keeps warnings as notices, and the English text older imports stored" do
    import = create(warnings: [notice, "line 3: an old warning"])

    expect(repo.warnings(import)).to eq([notice, "line 3: an old warning"])
    expect(repo.error(import)).to be_nil
  end

  it "keeps the warnings when an update doesn't change them" do
    import = create(warnings: [notice])

    updated = repo.update(import.id, rows_inserted: 3)
    expect(updated.rows_inserted).to eq(3)
    expect(repo.warnings(updated)).to eq([notice])

    expect(repo.warnings(repo.update(import.id, warnings: []))).to eq([])
  end

  it "reads the error as a notice, or as the text an older import stored" do
    expect(repo.error(create(status: "rejected", error: notice))).to eq(notice)

    old = create(status: "rejected")
    Hanami.app["db.gateway"].connection[:imports].where(id: old.id).update(error: "the file has no rows")
    expect(repo.error(repo.update(old.id))).to eq("the file has no rows")
  end
end
