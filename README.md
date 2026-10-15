# Tally

Personal finance tracker in Ruby ([Hanami 3](https://hanakai.org)) and SQLite. Imports bank statements, categorizes spending, and plans budgets and savings. Built to run on a Raspberry Pi Zero 2 W on the home network.

- [docs/architecture.md](docs/architecture.md): goals, data model, money rules, milestones
- [docs/statement-import.md](docs/statement-import.md): statement formats, re-import, categorization

**Status:** milestone 3 (categorization): statement import (Nubank account and card CSVs, Itaú card bill PDFs, re-imports that update instead of duplicating, transfers between your accounts), plus categories with a nature, generic rules, and a review list grouped by payee. The monthly report and cut suggestions are next.

## Requirements

- Ruby 3.3 or newer
- SQLite 3.37 or newer, including the `sqlite3` command (macOS ships it; on Debian/Raspberry Pi OS: `sudo apt install sqlite3`)
- poppler's `pdftotext`, to read Itaú bills (`brew install poppler`; `sudo apt install poppler-utils`)

## Getting started

```sh
bin/setup      # installs gems, creates the dev and test databases, installs the privacy pre-commit hook
bin/dev        # starts the server at http://localhost:2300
bundle exec rspec
```

The home page shows the SQLite settings in effect (WAL, foreign keys, full sync), which is a quick check on a new machine.

## Configuration

Settings come from environment variables, loaded from `.env` files in development (see [Hanami settings](https://hanakai.org/learn/hanami/app/settings)). Put real values in `.env.local`, which is gitignored.

| Variable | Default | |
|---|---|---|
| `DATABASE_URL` | `sqlite://db/tally.sqlite` | Use a path under `data/` for the live database. |
| `BASIC_AUTH_USERNAME`, `BASIC_AUTH_PASSWORD` | unset | Optional in development. In production the app answers 503 until both are set. |
| `HANAMI_MAX_THREADS` | `2` | Puma threads; 2 suits the Pi Zero 2 W. |
| `IMPORT_STORAGE_DIR` | `storage/imports` | Where each imported file is kept, named by its SHA-256. Gitignored. |
| `PASS_THROUGH_TOLERANCE_CENTS` | `5000` | How far the Itaú account's balance may drift from zero before the Accounts page warns. |

## Importing statements

Open **Import** and upload one or more files, or import from the command line:

```sh
bundle exec rake "tally:import[data/statements/*]"
```

| File | Name it like |
|---|---|
| Nubank account CSV | as exported: `NU_<account>_01JUN2026_30JUN2026.csv` (the period comes from the name) |
| Nubank card bill CSV | `Nubank_2026-09-09.csv`, the bill's due date |
| Itaú card bill PDF | anything |

Importing a file again updates its rows instead of duplicating them, flags rows that disappeared, and never touches what you edited. Itaú bills must add up to their printed totals to the cent, or they are rejected. Then open **Counterparties** and press "This is me" next to your own name, so a Pix between your accounts counts as a transfer. Details: [docs/statement-import.md](docs/statement-import.md).

To check the parsers against your real statements without committing them, put them in `data/statements/` (gitignored) and run `bundle exec rspec spec/local`.

Itaú bill fixtures are generated: after changing `spec/support/statements/itau_bills.rb`, run `bundle exec ruby spec/support/statements/build_fixtures.rb`.

## Categorizing

Imports categorize rows as they arrive: generic rules for public merchants (iFood, Uber, pharmacies, streaming…), Pix to people as Transferências (Pix), and Itaú's own category as a suggestion. Open **Review** for the rest: rows are grouped by payee, biggest first, and one pick with "always" covers that payee's past and future rows. **Categories** sets each category's nature (fixed, essential, discretionary) and how far the savings planner may cut it; **Rules** lists every rule with how many rows it covers.

The categories and generic rules are seeded by `bin/hanami db seed` (and on the first import). Rules about your own payees stay in your database; to keep some in a file, put them in `data/seeds.rb` (gitignored), which the seed loads.

## Money

All amounts are whole cents in `INTEGER` columns, carried in the app as `Tally::Money`. Never use floats.

```ruby
Tally::Money.parse("1.234,56")                 # Brazilian format => R$ 1.234,56
Tally::Money.parse("-518.54", decimal: ".")    # Nubank CSV format
Tally::Money.parse("1,005")                    # raises: more than 2 decimals is never rounded
Tally::Money.new(100).allocate([1, 1, 1])      # => 34, 33, 33 cents: parts always add up
```

## Personal data stays out of this repository

The repository is public. Real statements, the live database and anything derived from them go in `data/`, which is gitignored (as are `*.csv` and `*.pdf` outside `spec/fixtures/`). Tests use synthetic statements with fake names and amounts.

`bin/setup` installs `bin/check-private` as a git pre-commit hook. List the strings that must never be committed (your CPF, account numbers, names) in `data/private-patterns.txt`, one per line (`/.../` for a regex), and any commit that contains one is refused. Run `bin/check-private --all` to scan every tracked file.
