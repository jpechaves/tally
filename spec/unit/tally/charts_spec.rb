# frozen_string_literal: true

RSpec.describe Tally::Charts do
  def chart(**options)
    described_class.columns(format: ->(v) { "R$ #{v}" }, compact: ->(v) { "R$ #{v / 100}" }, title: "Income & spending",
      **options)
  end

  it "picks a clean axis top whose thirds are round" do
    expect([0, 7, 25_000, 892_000, 999_999, 1_234_567].map { described_class.nice_max(_1) })
      .to eq([300, 9, 30_000, 900_000, 1_200_000, 1_500_000])
  end

  it "draws a column per value, with its value on hover and the labels escaped" do
    svg = chart(labels: ["jul/2026", "<ago>"], highlight: 1,
      series: [{name: "Income", css: "s-income", values: [900_000, 0]}, {name: "Spending", css: "s-spending", values: [300_000, 150_000]}])

    expect(svg).to start_with(%(<svg viewBox="0 0 760 202" role="img" aria-label="Income &amp; spending">))
    expect(svg.scan(/<path class="mark /).size).to eq(3)
    expect(svg).to include("<title>jul/2026 · Income: R$ 900000</title>", "<title>&lt;ago&gt; · Income: R$ 0</title>")
    expect(svg).to include(%(class="current">&lt;ago&gt;</text>), ">R$ 9000</text>", %(<line class="baseline"))
    expect(svg.scan(/<g>/).size).to eq(svg.scan(%r{</g>}).size)
  end

  it "keeps columns at most 24px wide, rounded at the top" do
    svg = chart(labels: ["a"], series: [{name: "x", css: "s", values: [100]}])
    path = svg[/d="([^"]+)"/, 1]

    expect(path).to match(/\AM[\d.]+,176V[\d.]+Q/)
    xs = path.scan(/[MHQ]([\d.]+)/).flatten.map(&:to_f)
    expect(xs.max - xs.min).to be <= 24
  end

  it "gives bar widths as a share of the largest" do
    expect(described_class.percent(50, 200)).to eq(25.0)
    expect(described_class.percent(300, 200)).to eq(100.0)
    expect(described_class.percent(-5, 200)).to eq(0.0)
    expect(described_class.percent(5, 0)).to eq(0.0)
  end
end
