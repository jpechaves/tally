# Design

Tally looks like a dark product tool, after Linear's app: dense, quiet, and readable at a glance. The reference it follows is [design-linear.app.md](design-linear.app.md), an analysis of Linear's design system (colors, type, spacing, components); this page says how Tally applies it and where it departs (a product UI rather than a marketing site, red and green for bad and good, and two data colors for charts). The styles live in one file, `public/assets/app.css`, as custom properties at the top; templates use a handful of classes and no inline colors.

## Principles

- **One dark canvas, a ladder of surfaces.** The page is near-black (`--canvas` #010102). Panels, tables, stat tiles and charts sit one step up on charcoal (`--surface-1` #0f1011) with a 1px hairline border (`--hairline` #23252a) and 12px corners. Hover lifts a row one more step. No drop shadows, no gradients.
- **Light gray ink in four steps.** `--ink` for values and headings, `--ink-muted` for body text, `--ink-subtle` for labels and notes, `--ink-tertiary` for what's disabled or struck through.
- **One accent, used sparingly.** Lavender (`--accent` #5e6ad2) marks the current page in the sidebar, focus rings, and the one primary button on a page (import, make a plan, accept a plan, save a transaction). Every other button is a charcoal secondary button.
- **Red and green only mean bad and good.** Over budget, spending up, a rejected import or an error is red; saved money, a bill that matches, money freed is green. They always come with words, never color alone. The message an action leaves at the top of the page (`shared/message`) follows the same rule: green text on a faint green tint when it worked ("Changed the category of 2 rows."), red on a faint red tint when it didn't (a refused form, or a change that reached no row).
- **Type.** Inter if installed, otherwise the system's UI sans (SF Pro on a Mac). 14px body, 26px page titles at weight 600 with slightly negative tracking, 11.5px uppercase group labels. Numbers in tables use tabular figures so columns line up; big stat values don't.
- **Layout.** A 232px sidebar with the pages grouped by task (Overview, Planning, Data, Organize) and the language switch at the bottom. Below 860px it folds into a top bar, stat tiles go two per row, and wide tables scroll sideways inside their panel.

## Breadcrumb

Pages below a section show where they sit above the `<h1>`: small `--ink-subtle` crumbs, `›` between them, the lavender hover on links, and the current page last in `--ink-muted`, cut with an ellipsis when long. It is a `<nav>` with `aria-current="page"` on the last crumb (`app/templates/shared/_breadcrumb.html.erb`).

## Charts

Charts are drawn on the server as inline SVG (`Tally::Charts`) or plain HTML bars, so there is no charting library to ship to the Pi and nothing for the Content Security Policy to block.

- **Where:** income against spending by month on the home page (last 12 months) and the report (last 6); spending by category on the home page; installments committed per month; a meter per budget (spent against the limit, with a tick at how much of the month has gone by); a share bar beside each line of the report's tables.
- **Colors:** spending is lavender (`--series-spending` #5e6ad2), income is green-teal (`--series-income` #199e70). The pair passes a colorblind-safety check against the panel color (lightness band, chroma, color-vision-deficiency and normal-vision separation, 3:1 contrast). A budget over its limit turns its meter red.
- **Marks:** columns at most 24px wide, rounded 4px at the top and square at the baseline, 2px apart; hairline solid gridlines at clean values (the axis top is the first 1, 1.5, 2, 3, 4.5, 6 or 9 × 10ⁿ that fits); axis amounts compact ("R$ 3 mil", "R$ 3K"). The current month's label is bold.
- **Reading values:** hovering a column shows its month, series and amount (an SVG `<title>`). Every chart sits next to a table with the same numbers, so nothing depends on hovering or on color. Charts with two series have a legend.
