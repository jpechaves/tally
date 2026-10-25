# frozen_string_literal: true

RSpec.describe Tally::Charts do
  def chart(**options)
    described_class.columns(format: ->(v) { "R$ #{v}" }, compact: ->(v) { "R$ #{v / 100}" }, title: "Income & spending",
      **options)
  end

  it "picks a clean axis top whose thirds are round" do
    expect([0, 7, 25_000, 500, 892_000, 999_999, 1_234_567].map { described_class.nice_max(_1) })
      .to eq([300, 9, 30_000, 600, 900_000, 1_200_000, 1_500_000])
  end

  it "draws a column per value, with its value on hover and the labels escaped" do
    svg = chart(labels: ["jul/2026", "<ago>"], highlight: 1,
      series: [{name: "Income", css: "s-income", values: [900_000, 0]}, {name: "Spending", css: "s-spending", values: [300_000, 150_000]}])

    expect(svg).to start_with(%(<svg viewBox="0 0 760 202" role="img" aria-label="Income &amp; spending">))
    expect(svg.scan('<path class="mark ').size).to eq(3)
    expect(svg).to include("<title>jul/2026 · Income: R$ 900000</title>", "<title>&lt;ago&gt; · Income: R$ 0</title>")
    expect(svg).to include(%(class="current">&lt;ago&gt;</text>), ">R$ 9000</text>", %(<line class="baseline"))
    expect(svg.scan("<g>").size).to eq(svg.scan(%r{</g>}).size)
  end

  it "keeps columns at most 24px wide, rounded at the top" do
    svg = chart(labels: ["a"], series: [{name: "x", css: "s", values: [100]}])
    path = svg[/d="([^"]+)"/, 1]

    expect(path).to match(/\AM[\d.]+,176V[\d.]+Q/)
    xs = path.scan(/[MHQ]([\d.]+)/).flatten.map(&:to_f)
    expect(xs.max - xs.min).to be <= 24
  end

  it "places every gridline, column and label exactly" do
    svg = chart(labels: %w[a b], series: [{name: "In", css: "i", values: [300, 100]}, {name: "Out", css: "o", values: [150, -20]}])

    expect(svg.scan(/<line [^>]+>/)).to eq([
      %(<line class="baseline" x1="76" x2="760" y1="176.0" y2="176.0"/>),
      %(<line class="grid" x1="76" x2="760" y1="120.0" y2="120.0"/>),
      %(<line class="grid" x1="76" x2="760" y1="64.0" y2="64.0"/>),
      %(<line class="grid" x1="76" x2="760" y1="8.0" y2="8.0"/>)
    ])
    expect(svg.scan(/<text x="68" y="([\d.]+)" text-anchor="end">([^<]+)/))
      .to eq([["180.0", "R$ 0"], ["124.0", "R$ 1"], ["68.0", "R$ 2"], ["12.0", "R$ 3"]])
    expect(svg.scan(/<rect [^>]+>/).map { _1[/x="([\d.]+)"/, 1] }).to eq(%w[221.0 247.0 563.0 589.0])
    expect(svg.scan(/<rect [^>]+>/).uniq { _1.sub(/x="[\d.]+"/, "") }).to eq([%(<rect class="hit" x="221.0" y="8" width="26" height="168"/>)])
    expect(svg.scan(/<path [^>]+>/)).to eq([
      %(<path class="mark i" d="M222.0,176V12.0Q222.0,8.0 226.0,8.0H242.0Q246.0,8.0 246.0,12.0V176Z"/>),
      %(<path class="mark o" d="M248.0,176V96.0Q248.0,92.0 252.0,92.0H268.0Q272.0,92.0 272.0,96.0V176Z"/>),
      %(<path class="mark i" d="M564.0,176V124.0Q564.0,120.0 568.0,120.0H584.0Q588.0,120.0 588.0,124.0V176Z"/>)
    ])
    expect(svg.scan(/<text x="([\d.]+)" y="194" text-anchor="middle">([^<]+)/)).to eq([["247.0", "a"], ["589.0", "b"]])
  end

  it "rounds a short column only as much as its height, and a narrow one as half its width" do
    short = chart(labels: ["a"], series: [{name: "x", css: "s", values: [1]}, {name: "y", css: "s", values: [300]}])
    narrow = chart(labels: (1..30).map { "m#{_1}" },
      series: [{name: "x", css: "s", values: [3] * 30}, {name: "y", css: "s", values: [3] * 30}])

    expect(short[/d="([^"]+)"/, 1]).to eq("M393.0,176V176.0Q393.0,175.4 393.6,175.4H416.4Q417.0,175.4 417.0,176.0V176Z")
    expect(narrow[/d="([^"]+)"/, 1]).to eq("M80.4,176V11.0Q80.4,8.0 83.4,8.0H83.4Q86.4,8.0 86.4,11.0V176Z")
  end

  it "labels every other column when there are more than 12, and always the highlighted one" do
    svg = chart(labels: (1..14).map { "m#{_1}" }, highlight: 3, series: [{name: "x", css: "s", values: [1] * 14}])

    expect(svg.scan(/<text x="([\d.]+)" y="194" text-anchor="middle"( class="current")?>([^<]+)/)).to eq([
      ["100.4", nil, "m1"], ["198.1", nil, "m3"], ["247.0", %( class="current"), "m4"], ["295.9", nil, "m5"],
      ["393.6", nil, "m7"], ["491.3", nil, "m9"], ["589.0", nil, "m11"], ["686.7", nil, "m13"]
    ])
  end

  it "labels every column up to 12, and every other one from 13" do
    labels = ->(count) { chart(labels: (1..count).map { "m#{_1}" }, series: [{name: "x", css: "s", values: [1] * count}]).scan(/>m\d+</).size }

    expect([labels.call(12), labels.call(13)]).to eq([12, 7])
  end

  it "gives bar widths as a share of the largest" do
    expect(described_class.percent(1, 3)).to eq(33.3)
    expect(described_class.percent(50, 200)).to eq(25.0)
    expect(described_class.percent(300, 200)).to eq(100.0)
    expect(described_class.percent(-5, 200)).to eq(0.0)
    expect(described_class.percent(5, 0)).to eq(0.0)
  end

  describe ".map" do
    def place(name, lat, lon) = Tally::Places::Place.new(name:, lat:, lon:)

    def view(*places) = described_class.map(places, title: "Places")[/viewBox="([^"]+)"/, 1]

    it "draws a dot per place over the bundled world, named on hover" do
      svg = described_class.map([place("<Lisboa>", 0, 0)], title: "Where we went")

      expect(svg).to start_with(%(<svg class="map" viewBox="160 80 40 20" role="img" aria-label="Where we went">))
      expect(svg).to include(%(<use href="/assets/world.svg#world"/>), %(<g><title>&lt;Lisboa&gt;</title><circle cx="180" cy="90" r="0.36"/></g>))
    end

    it "zooms to the places, 2:1, inside the world" do
      expect(view(place("A", 60, -100), place("B", -40, 100))).to eq("70 25 220 110")
      expect(view(place("A", 0, 175))).to eq("320 80 40 20")
      expect(view(place("A", 80, -179), place("B", -80, 179))).to eq("0 0 360 180")
    end
  end
end
