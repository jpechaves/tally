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
    BASE = TOP + PLOT_HEIGHT

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
      slot = (WIDTH - LEFT).to_f / [labels.size, 1].max
      width = [((slot * 0.7) - (GAP * (series.size - 1))) / series.size, COLUMN_MAX].min.floor
      group = (width * series.size) + (GAP * (series.size - 1))
      y = y_scale(top)

      svg = frame(top, title, compact)
      labels.each_with_index do |label, index|
        left = LEFT + (slot * index) + ((slot - group) / 2)
        series.each_with_index do |one, position|
          value = one[:values][index].to_i
          x = (left + (position * (width + GAP))).round(1)
          svg << %(<g><title>#{h(label)} · #{h(one[:name])}: #{h(format.call(value))}</title>)
          svg << %(<rect class="hit" x="#{x - (GAP / 2.0)}" y="#{TOP}" width="#{width + GAP}" height="#{PLOT_HEIGHT}"/>)
          svg << %(<path class="mark #{one[:css]}" d="#{column_path(x, y.call(value), width, BASE)}"/>) if value.positive?
          svg << "</g>"
        end
      end
      svg << x_labels(labels, slot, highlight) << "</svg>"
    end

    # Lines over a shared axis of labels, one per series, with a dot on each value that
    # shows it on hover; a nil value (nothing that month) breaks the line. A dashed series
    # is a reference, such as the expected amount, drawn without dots.
    #
    # @param series [Array<Hash>] {name:, css:, values: [Integer, nil], dashed: Boolean}
    # @see .columns for the other parameters
    def lines(labels:, series:, format:, compact:, title:, highlight: nil)
      top = nice_max(series.flat_map { _1[:values] }.compact.max.to_i)
      slot = (WIDTH - LEFT).to_f / [labels.size, 1].max
      x = ->(index) { (LEFT + (slot * index) + (slot / 2)).round(1) }
      y = y_scale(top)

      svg = frame(top, title, compact)
      series.each do |one|
        points = one[:values].each_with_index.map { |value, index| value && [x.call(index), y.call(value).round(1)] }
        points.chunk_while { _1 && _2 }.select { _1.compact.size > 1 }.each do |run|
          svg << %(<path class="line #{one[:css]}#{" dashed" if one[:dashed]}" d="M#{run.map { _1.join(",") }.join("L")}"/>)
        end
        next if one[:dashed]

        points.each_with_index do |point, index|
          next unless point

          svg << %(<g><title>#{h(labels[index])} · #{h(one[:name])}: #{h(format.call(one[:values][index]))}</title>)
          svg << %(<circle class="dot #{one[:css]}" cx="#{point[0]}" cy="#{point[1]}" r="4"/></g>)
        end
      end
      svg << x_labels(labels, slot, highlight) << "</svg>"
    end

    # The world drawn as x = lon + 180, y = 90 - lat (public/assets/world.svg).
    WORLD = "/assets/world.svg#world"
    MAP_PAD = 5
    MAP_MIN_WIDTH = 40

    # A dot per place over the world map, zoomed to the places (2:1, inside the world),
    # each named on hover. The map is one cached file the page points at, not inlined.
    #
    # @param places [Array<Places::Place>] at least one
    def map(places, title:)
      xs = places.map { _1.lon + 180 }
      ys = places.map { 90 - _1.lat }
      width = [xs.max - xs.min + (2 * MAP_PAD), 2 * (ys.max - ys.min + (2 * MAP_PAD)), MAP_MIN_WIDTH].max.clamp(..360)
      height = width / 2.0
      left = (((xs.min + xs.max) / 2.0) - (width / 2.0)).clamp(0, 360 - width)
      top = (((ys.min + ys.max) / 2.0) - (height / 2.0)).clamp(0, 180 - height)
      radius = width / 110.0

      svg = %(<svg class="map" viewBox="#{[left, top, width, height].map { number(_1) }.join(" ")}" role="img" aria-label="#{h(title)}">)
      svg << %(<use href="#{WORLD}"/>)
      places.each_with_index do |place, index|
        svg << %(<g><title>#{h(place.name)}</title><circle cx="#{number(xs[index])}" cy="#{number(ys[index])}" r="#{number(radius)}"/></g>)
      end
      svg << "</svg>"
    end

    # Value -> y, from the baseline up to `top`.
    def y_scale(top) = ->(value) { BASE - (PLOT_HEIGHT * [value, 0].max / top.to_f) }

    # The <svg> opening and the gridlines at thirds of `top`, each with its amount.
    def frame(top, title, compact)
      y = y_scale(top)
      svg = %(<svg viewBox="0 0 #{WIDTH} #{BASE + AXIS_BAND}" role="img" aria-label="#{h(title)}">)
      (0..3).map { top * _1 / 3 }.each do |tick|
        line_y = y.call(tick).round(1)
        svg << %(<line class="#{tick.zero? ? "baseline" : "grid"}" x1="#{LEFT}" x2="#{WIDTH}" y1="#{line_y}" y2="#{line_y}"/>)
        svg << %(<text x="#{LEFT - 8}" y="#{line_y + 4}" text-anchor="end">#{h(compact.call(tick))}</text>)
      end
      svg
    end

    # The x axis labels under each slot (every other one past 12), the highlighted one bold.
    def x_labels(labels, slot, highlight)
      every = (labels.size > 12) ? 2 : 1
      labels.each_with_index.filter_map do |label, index|
        next unless (index % every).zero? || index == highlight

        css = (index == highlight) ? %( class="current") : ""
        %(<text x="#{(LEFT + (slot * index) + (slot / 2)).round(1)}" y="#{BASE + 18}" text-anchor="middle"#{css}>#{h(label)}</text>)
      end.join
    end

    # 160.0 -> "160", 0.123 -> "0.12"
    def number(value) = format("%.2f", value).sub(/\.?0+\z/, "")

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
