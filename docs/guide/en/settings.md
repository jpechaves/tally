# Settings, login, debug info and the privacy guard

## Settings

Settings live in `.env`; put your own values in `.env.local` (not committed). The full list is in the [README](../../../README.md#configuration). The ones you are most likely to change:

- `DEFAULT_LOCALE`: `pt-BR` or `en`.
- `TIME_ZONE`: for example `America/Sao_Paulo`.
- `DATABASE_URL`: where the database is.

## Login (basic auth)

Set both `BASIC_AUTH_USERNAME` and `BASIC_AUTH_PASSWORD` in `.env.local` and restart: the browser asks for them. Leave both empty for no login. With only one set, Tally answers 503 until you fix it.

## Debug info

Sidebar, bottom: **Debug info**. Shows the SQLite version and settings (journal mode, foreign keys, synchronous, busy timeout). Look at it on a new machine or after a database problem.

![Debug info](../images/en/debug.png)

## Privacy guard

The repository is public. Put strings that must never be committed (your CPF, account numbers, names) in `data/private-patterns.txt`, one per line (`/regex/` works too). This file is not committed.

- `bin/setup` installs `bin/check-private` as a pre-commit hook: a commit containing one of them is refused.
- `bin/check-private --all` scans every tracked file.
