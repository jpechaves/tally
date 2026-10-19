# frozen_string_literal: true

RSpec.describe Tally::Merchants do
  describe ".stable_name" do
    {
      "LOJA EXEMPLO*AB12" => "LOJA EXEMPLO",
      "AEREA EXEMPLO * HX99" => "AEREA EXEMPLO",
      "PAG*Loja Exemplo" => "Loja Exemplo",
      "MP *LOJA EXEMPLO" => "LOJA EXEMPLO",
      "FARMACIA EXEMPLO 0123" => "FARMACIA EXEMPLO",
      "FARMACIA EXEMPLO 0123S" => "FARMACIA EXEMPLO",
      "PADARIA 24 HORAS" => "PADARIA 24 HORAS",
      "LOJA 123" => "LOJA",
      "Turismo B" => "Turismo",
      "TURISMO" => "TURISMO",
      "A" => "A",
      "*" => "*"
    }.each do |name, stable|
      it "reads #{name.inspect} as #{stable.inspect}" do
        expect(described_class.stable_name(name)).to eq(stable)
      end
    end
  end

  it "keys names regardless of case, spaces, punctuation and accents" do
    keys = ["Café Exemplo", "CAFE EXEMPLO", "CafeExemplo", "cafe-exemplo*XYZ"].map { described_class.key(_1) }

    expect(keys.uniq).to eq(["CAFEEXEMPLO"])
  end

  it "keys a name with no letters or digits by the name itself" do
    expect(described_class.key(" * ")).to eq("*")
  end
end
