# frozen_string_literal: true

require "cgi"

module Tally
  # Charts drawn on the server as inline SVG: no JavaScript bundle to ship to the Pi, and
  # nothing for the Content Security Policy to block. Marks follow docs/design.md: columns
  # at most 24px wide with 4px rounded tops on one baseline, hairline gridlines, and each
  # mark's value in a <title>, which browsers show on hover. Every chart sits next to a
  # table with the same numbers.
  module Charts
    WIDTH = 760
    PLOT_HEIGHT = 168
    TOP = 8
    LEFT = 76
    AXIS_BAND = 26
    COLUMN_MAX = 24
    GAP = 2
    RADIUS = 4

    module_function

    # Columns over a shared axis of labels, one per series side by side.
    #
    # @param labels [Array<String>] the x axis, e.g. months
    # @param series [Array<Hash>] {name:, css:, values: [Integer]}; negatives draw as 0
    # @param format [#call] value -> the full text shown on hover
    # @param compact [#call] value -> a short tick label
    # @param title [String] what the chart shows, for screen readers
    # @param highlight [Integer, nil] index of the label to emphasize (e.g. this month)
    def columns(labels:, series:, format:, compact:, title:, highlight: nil)
      top = nice_max(series.flat_map { _1[:values] }.max.to_i)
      ticks = (0..3).map { top * _1 / 3 }
      plot_width = WIDTH - LEFT
      slot = plot_width.to_f / [labels.size, 1].max
      width = [((slot * 0.7) - (GAP * (series.size - 1))) / series.size, COLUMN_MAX].min.floor
      group = (width * series.size) + (GAP * (series.size - 1))
      base = TOP + PLOT_HEIGHT
      y = ->(value) { base - (PLOT_HEIGHT * [value, 0].max / top.to_f) }

      svg = +%(<svg viewBox="0 0 #{WIDTH} #{base + AXIS_BAND}" role="img" aria-label="#{h(title)}">)
      ticks.each do |tick|
        line_y = y.(tick).round(1)
        svg << %(<line class="#{tick.zero? ? "baseline" : "grid"}" x1="#{LEFT}" x2="#{WIDTH}" y1="#{line_y}" y2="#{line_y}"/>)
        svg << %(<text x="#{LEFT - 8}" y="#{line_y + 4}" text-anchor="end">#{h(compact.(tick))}</text>)
      end

      every = labels.size > 12 ? 2 : 1
      labels.each_with_index do |label, index|
        left = LEFT + (slot * index) + ((slot - group) / 2)
        series.each_with_index do |one, position|
          value = one[:values][index].to_i
          x = (left + (position * (width + GAP))).round(1)
          svg << %(<g><title>#{h(label)} · #{h(one[:name])}: #{h(format.(value))}</title>)
          svg << %(<rect class="hit" x="#{x - (GAP / 2.0)}" y="#{TOP}" width="#{width + GAP}" height="#{PLOT_HEIGHT}"/>)
          svg << %(<path class="mark #{one[:css]}" d="#{column_path(x, y.(value), width, base)}"/>) if value.positive?
          svg << "</g>"
        end
        next unless (index % every).zero? || index == highlight

        css = index == highlight ? %( class="current") : ""
        svg << %(<text x="#{(LEFT + (slot * index) + (slot / 2)).round(1)}" y="#{base + 18}" text-anchor="middle"#{css}>#{h(label)}</text>)
      end
      svg << "</svg>"
    end

    # A column from the baseline up to `top`, square at the base and rounded at the top.
    def column_path(x, top, width, base)
      radius = [RADIUS, (base - top), width / 2.0].min
      top = top.round(1)
      "M#{x},#{base}V#{(top + radius).round(1)}Q#{x},#{top} #{(x + radius).round(1)},#{top}" \
        "H#{(x + width - radius).round(1)}Q#{x + width},#{top} #{x + width},#{(top + radius).round(1)}V#{base}Z"
    end

    # The axis top: the first 1, 1.5, 2, 3 or 5 x 10^n step whose thirds are clean and
    # that is at least the largest value.
    def nice_max(value)
      return 300 if value <= 0

      magnitude = 10**Math.log10(value).floor
      [1, 1.5, 2, 3, 4.5, 6, 9, 10].map { (_1 * magnitude).round }.find { _1 >= value && (_1 % 3).zero? } || (magnitude * 12)
    end

    # Width of a horizontal bar as a percentage of the largest, for style="width: …".
    def percent(value, max) = max.to_i.positive? ? (100.0 * [value, 0].max / max).clamp(0.0, 100.0).round(1) : 0.0

    def h(text) = CGI.escapeHTML(text.to_s)
  end
end
