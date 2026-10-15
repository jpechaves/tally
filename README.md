# Tally

Personal finance tracker in Ruby ([Hanami 3](https://hanakai.org)) and SQLite. Imports bank statements, categorizes spending, and plans budgets and savings. Built to run on a Raspberry Pi Zero 2 W on the home network.

- [docs/architecture.md](docs/architecture.md): goals, data model, money rules, milestones
- [docs/statement-import.md](docs/statement-import.md): statement formats, re-import, categorization

**Status:** milestone 1 (skeleton): the app, SQLite settings, the `Money` value object and basic auth. Statement import is next.

## Requirements

- Ruby 3.3 or newer
- SQLite 3.37 or newer, including the `sqlite3` command (macOS ships it; on Debian/Raspberry Pi OS: `sudo apt install sqlite3`)

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
