# frozen_string_literal: true

# Rewrites the synthetic Itaú bill fixtures:
#
#   bundle exec ruby spec/support/statements/build_fixtures.rb
#
# spec/importers/itau_card_pdf_spec.rb checks that the committed files match this output.
if $PROGRAM_NAME == __FILE__
  require_relative "fake_itau_bill"
  require_relative "itau_bills"

  dir = File.expand_path("../../fixtures/statements", __dir__)
  ItauBills::FIXTURES.each do |name, bill|
    File.binwrite(File.join(dir, name), ItauBills.public_send(bill).to_pdf)
    puts "wrote spec/fixtures/statements/#{name}"
  end
end
