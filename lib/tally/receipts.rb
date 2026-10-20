# frozen_string_literal: true

require "digest"
require "fileutils"
require "securerandom"

module Tally
  # Receipt files of home bills (issue #113, docs/architecture.md, section 8.9), kept on
  # disk under their SHA-256, so they never change and the same file is kept once. Only
  # JPEG, PNG and PDF, told apart by their first bytes, not by the name they came with.
  module Receipts
    Stored = Data.define(:sha256, :mime, :byte_size)

    MAX_BYTES = 10 * 1024 * 1024
    SIGNATURES = {"image/jpeg" => "\xFF\xD8\xFF".b, "image/png" => "\x89PNG\r\n\x1A\n".b, "application/pdf" => "%PDF-".b}.freeze
    SHA256 = /\A\h{64}\z/

    module_function

    # Settings#receipt_storage_dir, under the app root when relative.
    def dir = File.expand_path(Hanami.app["settings"].receipt_storage_dir, Hanami.app.root)

    # @return [Stored, :not_allowed, :too_big]
    def store(dir, io)
      content = io.read(MAX_BYTES + 1).to_s.b
      return :too_big if content.bytesize > MAX_BYTES

      mime = SIGNATURES.find { |_, signature| content.start_with?(signature) }&.first
      return :not_allowed unless mime

      stored = Stored.new(sha256: Digest::SHA256.hexdigest(content), mime:, byte_size: content.bytesize)
      write(path(dir, stored.sha256), content)
      stored
    end

    def path(dir, sha256)
      raise ArgumentError, "not a SHA-256: #{sha256.inspect}" unless sha256.match?(SHA256)

      File.join(dir, sha256)
    end

    def delete(dir, sha256) = FileUtils.rm_f(path(dir, sha256))

    # Written to a temporary file and renamed, so a file is never seen half written.
    def write(path, content)
      return if File.exist?(path)

      FileUtils.mkdir_p(File.dirname(path))
      temporary = "#{path}.#{SecureRandom.hex(4)}.tmp"
      File.binwrite(temporary, content)
      File.rename(temporary, path)
    end
  end
end
