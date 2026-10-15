# frozen_string_literal: true

# The synthetic Itaú bills behind spec/fixtures/statements/itau_*.pdf. Everything here is
# made up. Tests can also build variants (e.g. a bill whose rows don't add up).
module ItauBills
  Row = FakeItauBill::Row

  module_function

  def row(date, description, amount, detail = nil) = Row.new(date:, description:, amount:, detail:)

  # Closing 2026-10-02. Two-column and three-column pages, installments from the previous
  # year, refunds, two identical parking charges, a fee and its discount.
  def october(**overrides)
    FakeItauBill.new(
      closing: "02/10/2026", due: "09/10/2026",
      previous_total: "3.456,78",
      payments: [row("02/09", "Pagamento via conta", "-3.456,78")],
      purchases: [
        row("23/11", "LOJA EXEMPLO 11/12", "249,99", "outros SAO PAULO"),
        row("27/12", "PADARIA EXEMPLOSAO 10/10", "16,99", "supermercado SAO PAULO"),
        row("02/02", "VOO EXEMPLO*AB12 08/10", "1.504,14", "viagem SAO PAULO"),
        row("01/09", "MERCADO EXEMPLOSAO PAUL", "189,30", "supermercado SAO PAULO"),
        row("01/09", "ESTACIONAMENTO EXEMPLO", "14,00", "outros SAO PAULO"),
        row("01/09", "ESTACIONAMENTO EXEMPLO", "14,00", "outros SAO PAULO"),
        row("05/09", "CAFE EXEMPLOSAO PAULOBR", "91,30", "restaurante SAO PAULO"),
        row("06/09", "MARKETPLACE*EXEMPLO", "-114,50", "outros CAMPINAS"),
        row("09/09", "LIVRARIA EXEMPLO", "32,90", "educação SAO PAULO"),
        row("09/09", "CANCELAMENTO DE COMPRA", "-32,90", "educação SAO PAULO"),
        row("12/09", "FARMACIA EXEMPLO 4021", "63,47", "saúde SAO PAULO"),
        row("14/09", "LOJA ROUPAS EXEMPLO 01/02", "133,75", "vestuário SAO PAULO"),
        row("20/09", "PET EXEMPLO*PETL", "257,86", "outros SAO PAULO"),
        row("22/09", "SUPERMARKET EX", "58,54", "SUPERMARKET SAO PAULO"),
        row("25/09", "CANCELAMENTO PARCIAL DE", "-64,66", "outros Sao Paulo"),
        row("28/09", "ASSINATURA EXEMPLO", "44,90", "serviços SAO PAULO"),
        row("30/09", "POSTO EXEMPLO", "150,00")
      ],
      fees: [
        row("02/09", "Mensalidade - Plano do", "105,00", "Anuidade Diferenciada"),
        row("14/09", "Redução Mensalidade - P", "-52,50", "Anuidade Diferenciada")
      ],
      future: [
        row("23/11", "LOJA EXEMPLO 12/12", "249,99"),
        row("02/02", "VOO EXEMPLO*AB12 09/10", "1.504,14"),
        row("14/09", "LOJA ROUPAS EXEMPLO 02/02", "133,75")
      ],
      later: "1.512,42",
      cardholder: "MARIA E SOUZA",
      credit_limit: "10.000,00", available_limit: "4.321,09",
      layout: [[50, 310], [30, 220, 410]],
      split: [6, 5, 3, 3],
      **overrides
    )
  end

  # Closing 2027-01-02: rows from November and December belong to 2026. Drawn with tight
  # letter spacing, so poppler splits every word into fragments.
  def january_tight(**overrides)
    FakeItauBill.new(
      closing: "02/01/2027", due: "09/01/2027",
      previous_total: "2.100,00",
      payments: [row("02/12", "Pagamento via conta", "-2.100,00")],
      purchases: [
        row("15/11", "LOJA EXEMPLO 03/10", "120,00", "casa SAO PAULO"),
        row("20/12", "PADARIA EXEMPLOSAO PAUL", "45,60", "supermercado SAO PAULO"),
        row("28/12", "RESTAURANTE EXEMPLO", "230,00", "restaurante SAO PAULO"),
        row("28/12", "RESTAURANTE EXEMPLO", "230,00", "restaurante SAO PAULO"),
        row("01/01", "TRANSPORTE EXEMPLO", "27,90", "serviços SAO PAULO"),
        row("02/01", "LOJA ONLINE EXEMPLO", "-15,00", "outros SAO PAULO")
      ],
      fees: [
        row("02/12", "Mensalidade - Plano do", "105,00", "Anuidade Diferenciada"),
        row("14/12", "Redução Mensalidade - P", "-52,50", "Anuidade Diferenciada")
      ],
      future: [row("15/11", "LOJA EXEMPLO 04/10", "120,00")],
      later: "840,00",
      cardholder: "MARIA E SOUZA",
      credit_limit: "10.000,00", available_limit: "8.123,45",
      layout: [[50, 310], [50]],
      split: [3, 3],
      tight: true,
      **overrides
    )
  end

  FIXTURES = {
    "itau_2026-10.pdf" => :october,
    "itau_2027-01_tight.pdf" => :january_tight
  }.freeze
end
