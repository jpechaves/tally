# frozen_string_literal: true

require "stringio"
require "tmpdir"

RSpec.describe Tally::Receipts do
  around { |example| Dir.mktmpdir { |dir| @dir = dir and example.run } }

  let(:png) { "\x89PNG\r\n\x1A\n".b + "fake image".b }

  it "keeps a JPEG, PNG or PDF once, named by its SHA-256" do
    stored = described_class.store(@dir, StringIO.new(png))
    expect(stored).to eq(described_class::Stored.new(sha256: Digest::SHA256.hexdigest(png), mime: "image/png", byte_size: png.bytesize))
    expect(File.binread(described_class.path(@dir, stored.sha256))).to eq(png)
    expect(described_class.store(@dir, StringIO.new(png))).to eq(stored)
    expect(Dir.children(@dir)).to eq([stored.sha256])

    expect(described_class.store(@dir, StringIO.new("\xFF\xD8\xFF\xE0jpeg".b)).mime).to eq("image/jpeg")
    expect(described_class.store(@dir, StringIO.new("%PDF-1.7 fake".b)).mime).to eq("application/pdf")
  end

  it "refuses other files and files over the limit" do
    expect(described_class.store(@dir, StringIO.new("<svg/>"))).to eq(:not_allowed)
    stub_const("#{described_class}::MAX_BYTES", 8)
    expect(described_class.store(@dir, StringIO.new(png))).to eq(:too_big)
    expect(Dir.children(@dir)).to be_empty
  end

  it "deletes a file, and only a SHA-256 names one" do
    stored = described_class.store(@dir, StringIO.new(png))
    described_class.delete(@dir, stored.sha256)
    expect(Dir.children(@dir)).to be_empty
    expect { described_class.path(@dir, "../etc/passwd") }.to raise_error(ArgumentError)
  end
end
