# Tally: Architecture and Data Model

Tally tracks household spending, shows where the money goes, and plans savings. It runs on a Raspberry Pi Zero 2 W on the home network.

Companion: [statement-import.md](statement-import.md) (parsers, re-import rules, categorization rules).

> All names, account numbers and amounts in these docs are made up. The repository is public, so real statements and anything derived from them stay out of it (§17).

## TL;DR

- **Why the app exists:** to show where your money goes, point out what you can cut, and answer "if I want to save R$ X a month, what has to change?" with a concrete per-category plan that you can track every month.
- **Data in:** four statement sources: the Nubank account CSV (where the salary lands), the Nubank card CSV, the Itaú card PDF and the Nubank Conta Global CSV (in dollars, checked against its running balance). Importing the same file again updates rows instead of duplicating them. An Itaú bill that doesn't add up to its printed total to the cent is rejected, and each Nubank card bill is checked against the payment that settled it.
- **No double counting:** moving money between your own accounts (Pix to your other bank, paying the card, RDB savings) is a transfer, not spending. Spending is counted once: on card purchases, and on Pix, boleto or debit payments to other people and companies.
- **Categorization:** company tax ID (CNPJ) rules first, then Itaú's own category as a suggestion, then a review list grouped by who you paid. Every category is also tagged **fixed**, **essential** or **discretionary**, which is what the cut suggestions and the savings planner work from.
- **Insights:** where the money went (by category and by payee, vs your 3-month average), cut candidates (discretionary spending, recurring charges, many small purchases, fees, installments), and when current installments end.
- **Savings planner:** you enter a monthly target. The app compares it with what you actually saved over the last 3 months, and spreads the gap across discretionary and flexible categories, never fixed ones. Once you accept the plan it becomes next month's budgets, and the dashboard shows whether you're on pace. Plain arithmetic you can check, no AI.
- **Stack:** Ruby 3.3+, Hanami 3.0 (ROM, dry-rb), SQLite, server-rendered pages. Runs on the Pi Zero 2 W; you open it from a laptop or phone over home Wi-Fi.
- **Precision and reliability:** whole centavos in integer columns, the database rejects anything else; WAL with full sync, nightly backup off the SD card.
- **Deterministic first:** version 1 uses only rules and arithmetic. Smarter features (learned categorization, unusual-spending alerts, optional AI advice) come later as suggestions you approve. See §14 and §15.
- **Milestones:** skeleton → import → categorization → insights → savings planner and budgets → localization (Portuguese and English) → design and charts → Pi deployment → phase 2 smart suggestions (§12).

## 1. Goals and constraints

The app answers four questions, in this order:
1. **Where does my money go?** Every transaction imported and categorized.
2. **What can I cut?** Ranked suggestions with an R$/month value each.
3. **If I want to save R$ X a month, what should I do?** A per-category plan that closes the gap.
4. **Am I on track this month?** Budget vs spent, at the current pace.

Constraints:
- Single household, LAN only. The Pi is the single live instance; a laptop is for development.
- Raspberry Pi Zero 2 W: quad Cortex-A53 @ 1 GHz, **512 MB RAM**, SD card storage.
- Priorities, in order: **precise**, **reliable**, **light**, fast enough.

## 2. How the money moves (what the app has to model)

`[imported]` marks the statement sources. Not drawn: Nubank Conta Global, a dollar account topped up from Nubank conta ("Conversão para Conta Global", a transfer) whose own card purchases abroad are spending in dollars, kept apart from the reais. Arrows marked `transfer` are between your own accounts and never count as spending or income.

```
        Employer (salary)               Own company (pró-labore)
              │ income                        │ income
              ▼                               ▼
        ┌───────────────────────────────────────────┐
        │        Nubank conta   [imported, CSV]     │──── Pix / boleto ───▶ bills, people, shops
        │        (checking)                         │      = spending
        └───────────────────────────────────────────┘
          │ transfer          │ "Pagamento de      │ transfer
          │ "Aplicação/       │  fatura"           │ Pix to yourself
          │  Resgate RDB"     │                    │
          ▼                   ▼                    ▼
   ┌──────────────┐   ┌────────────────┐   ┌──────────────────┐
   │ Nubank RDB   │   │ Nubank cartão  │   │   Itaú conta     │
   │ (savings,    │   │ [imported,CSV] │   │ not imported;    │
   │  balance     │   │ purchases =    │   │ pass-through:    │
   │  from the    │   │ spending       │   │ Pix ≈ bill       │
   │  transfers)  │   │                │   │                  │
   └──────────────┘   └────────────────┘   └──────────────────┘
                                                   │ transfer "Pagamento via conta"
                                                   ▼
                                           ┌──────────────────┐
                                           │ Itaú cartão      │──▶ shops = spending
                                           │ [imported, PDF]  │    (itemized, with installments)
                                           └──────────────────┘
```

What counts:
- **Income**: money received from anyone who is not you.
- **Spending**: purchases on both cards, and Pix, boleto or debit payments to anyone who is not you.
- **Saved**: income minus spending. Money moved to RDB is one place it can sit, but the planner measures savings as income minus spending, wherever the money ends up.

## 3. System overview

```
  Laptop / phone browser
          │  HTTP over home Wi-Fi (basic auth)
          ▼
┌────────────────────── Raspberry Pi Zero 2 W ──────────────────────┐
│  systemd ─▶ Puma (1 process, 2 threads)                           │
│               │                                                   │
│               ▼                                                   │
│   Hanami app                                                      │
│   ┌─────────┐   ┌─────────────┐   ┌────────┐   ┌──────────────┐   │
│   │ Actions │──▶│ Operations  │──▶│ Repos  │──▶│ SQLite file  │   │
│   │ (HTTP)  │   │ (rules, DB  │   │(queries│   │ WAL, FULL    │   │
│   └─────────┘   │ transaction)│   └────────┘   │ sync, FKs on │   │
│                 └─────────────┘                └──────────────┘   │
│                    │        │                        │            │
│                    ▼        ▼                        │ nightly    │
│             Importers   Categorizer                  ▼ .backup    │
│             (CSV, PDF   (rules)                 USB stick /       │
│              via poppler)                       laptop (rsync)    │
└───────────────────────────────────────────────────────────────────┘
```

## 4. Stack (checked against hanakai.org and rubygems.org on 2026-10-15)

| Piece | Choice | Version | Notes |
|---|---|---|---|
| Ruby | MRI | **3.3+** | `hanami` 3.0.x gemspec requires `>= 3.3`. |
| Web framework | Hanami | 3.0.2 | Routes, actions, views, settings, operations. |
| Persistence | hanami-db → ROM 5.4 + rom-sql 3.7 (on Sequel) | hanami-db 3.0.0 | Relations, repos, immutable structs. Sequel migrations in `config/db/migrate`. |
| Business logic | dry-operation (Hanami operations) | 1.1 | `step` / `transaction do ... end`, `Success` / `Failure`. |
| Validation and types | dry-validation, dry-types | 1.11 / 1.9 | Contracts for every form input. |
| Database | SQLite 3 via `sqlite3` gem | 2.10 | Precompiled for `aarch64-linux-gnu` and `arm-linux-gnu`, so no C compile on the Pi. |
| App server | Puma | 8.x | Single mode, 2 threads. |
| Front end | Server-rendered HTML (ERB) + one small CSS file | n/a | No Node toolchain (`--skip-assets`). |
| CSV import | Ruby stdlib `csv` | bundled | Nubank account and card statements. |
| PDF import | poppler-utils `pdftotext -bbox` | Debian package | Itaú card bills. The `pdf-reader` gem drops spaces inside merchant names on these PDFs. |
| Tests | RSpec | n/a | Golden-file tests per parser on synthetic statements, re-import tests, money tests. |

The app was generated with:

```sh
gem install hanami
hanami new tally --skip-assets --skip-mailer   # --database defaults to sqlite
```

## 5. Money: the precision rules

Implemented in `lib/tally/money.rb` (milestone 1).

1. **Integer centavos** in `INTEGER` columns named `*_cents`. Never `REAL`/`Float`, never `NUMERIC`.
2. **Signed amounts**: negative = money out of the account, positive = money in. Balances are a plain `SUM`.
3. **A `Money` value object** (`cents: Integer`, `currency: String`) carries every amount through the app. Integer arithmetic only; mixing currencies raises.
4. **Parse at the edges with `BigDecimal`**: `"1.234,56"` (Itaú, forms) and `-518.54` (Nubank CSV) both become cents. More than 2 decimals is rejected, never silently rounded.
5. **Division** (splits, percentages) uses `Money#allocate` with the largest-remainder method, so parts always add back up to the total.
6. **The database enforces it**: SQLite `STRICT` tables (Sequel's `create_table(..., strict: true)`), so a `12.5` in an `INTEGER` column is an error, not a stored value.
7. **One currency per account.** Amounts are stored in their account's currency (`accounts.currency`): BRL everywhere except Nubank Conta Global, in USD. Nothing converts between them. The report, cuts, budgets and the category and counterparty totals count only BRL accounts; a list over several currencies shows a total per currency.

## 6. Data model

```
                         ┌──────────────┐
                         │   imports    │ one row per file ever imported
                         └──────┬───────┘
                                │ first/last import
┌──────────┐  1     n  ┌────────▼───────────┐  n     1  ┌────────────────┐
│ accounts │──────────▶│    transactions    │◀──────────│ counterparties │
└────┬─────┘           │  amount_cents ±    │           │ name, CNPJ/CPF │
     │                 │  kind, category,   │           │ is_self        │
     │ 1               │  external_id …     │           └────────────────┘
     │                 └──┬──────┬───────┬──┘
     │ n                  │      │       │ n:1
┌────▼────────────┐       │      │  ┌────▼───────┐  n   1  ┌────────────────┐
│ card_statements │◀──────┘      │  │ categories │◀─────────│ category_rules │
│ (one per bill)  │  n:1         │  └────▲───────┘          └────────────────┘
└─────────────────┘              │       │ 1:n
                          ┌──────▼────┐  ┌┴─────────┐  n   1  ┌───────────────┐
                          │ transfers │  │ budgets  │─────────▶│ savings_plans │
                          │ (2 legs)  │  └──────────┘          │ + plan lines  │
                          └───────────┘                        └───────────────┘
```

All tables: `id INTEGER PRIMARY KEY`, `created_at` / `updated_at` as ISO-8601 UTC text. Money-event dates are `TEXT 'YYYY-MM-DD'`.

```
accounts                        -- created in milestone 1
  name                  TEXT NOT NULL UNIQUE      -- "Nubank conta", "Nubank cartão", "Itaú cartão", "Nubank RDB", "Itaú conta"
  kind                  TEXT NOT NULL  -- checking | credit_card | investment | cash
  institution           TEXT NULL      -- nubank | itau
  external_ref          TEXT NULL      -- account or card number as the bank prints it (e.g. "12345678", last 4 digits)
  currency              TEXT NOT NULL DEFAULT 'BRL'
  opening_balance_cents INTEGER NOT NULL DEFAULT 0
  archived_at           TEXT NULL
  mirror_transfers      INTEGER NOT NULL DEFAULT 0   -- no statement of its own: transfers are mirrored into it (milestone 2)

categories
  name          TEXT NOT NULL
  parent_id     INTEGER NULL REFERENCES categories(id)   -- one level: Moradia > Energia
  kind          TEXT NOT NULL   -- expense | income
  nature        TEXT NULL       -- expenses only: fixed | essential | discretionary (see §8)
  max_cut_pct   INTEGER NULL    -- how far the planner may cut it; defaults by nature: 0 / 15 / 50
  archived_at   TEXT NULL
  UNIQUE(parent_id, name), and UNIQUE(name) among top-level categories (two partial indexes)

counterparties                  -- who the money went to / came from
  name            TEXT NOT NULL
  document        TEXT NULL     -- full CNPJ, or masked CPF "•••.123.456-••"
  document_kind   TEXT NULL     -- cnpj | cpf_masked
  bank_name, bank_code, branch, account_number  TEXT NULL
  is_self         INTEGER NOT NULL DEFAULT 0     -- you, at another bank → transfer
  match_key       TEXT NOT NULL UNIQUE           -- "document|NAME": UNIQUE(document, name) would let NULL documents repeat
  default_category_id INTEGER NULL REFERENCES categories(id)
  display_name    TEXT NULL     -- your name for it, shown instead of `name` (COALESCE in the repos); imports never write it
  note            TEXT NULL     -- your line about it, shown on the counterparty and its rows
  UNIQUE(document, name)

transactions
  account_id        INTEGER NOT NULL REFERENCES accounts(id)
  occurred_on       TEXT NOT NULL     -- date that counts for reports and budgets
  purchased_on      TEXT NULL         -- original purchase date (card installments)
  amount_cents      INTEGER NOT NULL CHECK (amount_cents <> 0)
  kind              TEXT NOT NULL     -- purchase | refund | fee | income | transfer | bill_payment
  category_id       INTEGER NULL REFERENCES categories(id)
  category_source   TEXT NOT NULL DEFAULT 'none'   -- none | bank | rule | manual (manual is never overwritten)
  category_rule_id  INTEGER NULL REFERENCES category_rules(id)
  transfer_id       INTEGER NULL REFERENCES transfers(id)
  counter_account_id INTEGER NULL REFERENCES accounts(id)   -- transfers: the other account, known before its leg is imported
  counterparty_id   INTEGER NULL REFERENCES counterparties(id)
  description       TEXT NOT NULL     -- cleaned
  raw_description   TEXT NOT NULL     -- exactly as in the statement
  bank_category     TEXT NULL         -- Itaú's "vestuário", "supermercado", …
  location          TEXT NULL         -- Itaú's city
  installment_number, installment_total  INTEGER NULL
  purchase_key      TEXT NULL         -- links installments of one purchase across bills
  card_statement_id INTEGER NULL REFERENCES card_statements(id)
  memo              TEXT NULL         -- yours; imports never touch it
  external_id       TEXT NULL         -- upsert key (Nubank UUID, or derived for Itaú)
  first_import_id, last_import_id, missing_since_import_id  INTEGER NULL REFERENCES imports(id)
  exchange_currency TEXT NULL         -- the other side of a currency exchange (GBP for a purchase abroad, BRL for a top-up)
  exchange_amount_cents INTEGER NULL  -- that amount, when the statement prints it
  exchange_rate     TEXT NULL         -- units of exchange_currency per unit of the account's currency, decimal text
  fee_cents         INTEGER NULL      -- the bank's fee, already inside amount_cents
  raw_json          TEXT NULL         -- parsed source row, for audit
  UNIQUE(account_id, external_id)
  INDEX (account_id, occurred_on), INDEX (category_id, occurred_on), INDEX (counterparty_id)

transfers                       -- exactly two legs that sum to 0, or match through the rate between currencies (one leg until the other account is imported)
  occurred_on   TEXT NOT NULL
  memo          TEXT NULL

imports                         -- one row per file, including re-imports
  account_id, source, file_name, file_sha256, period_start, period_end
  status        TEXT NOT NULL   -- applied | duplicate_file | rejected
  rows_inserted, rows_updated, rows_unchanged, rows_missing  INTEGER NOT NULL DEFAULT 0
  error         TEXT NULL       -- original file kept at storage/imports/<sha256>.<ext>

card_statements                 -- one per bill (fatura)
  account_id, closing_on, due_on
  total_cents, previous_total_cents, payments_cents, purchases_cents, fees_cents
  next_statement_cents, later_statements_cents   -- installments already committed
  credit_limit_cents, available_limit_cents
  import_id
  UNIQUE(account_id, due_on)

category_rules
  priority      INTEGER NOT NULL DEFAULT 100   -- lower runs first
  field         TEXT NOT NULL   -- counterparty_document | counterparty_name | description | bank_category | kind
  operator      TEXT NOT NULL   -- equals | contains | starts_with | regex
  pattern       TEXT NOT NULL
  amount_min_cents, amount_max_cents  INTEGER NULL
  category_id   INTEGER NOT NULL REFERENCES categories(id)
  origin        TEXT NOT NULL   -- seed | learned | manual
  hits          INTEGER NOT NULL DEFAULT 0
  disabled_at   TEXT NULL       -- switched off, not deleted, so a removed seed rule stays removed

savings_plans                   -- one per accepted "save X a month" plan
  target_cents      INTEGER NOT NULL CHECK (target_cents > 0)
  baseline_from, baseline_to   TEXT NOT NULL   -- months used as "what you do today", e.g. 2026-07..2026-09
  baseline_income_cents, baseline_spending_cents  INTEGER NOT NULL
  starts_month      TEXT NOT NULL   -- YYYY-MM
  status            TEXT NOT NULL   -- draft | active | replaced
  shortfall_cents   INTEGER NOT NULL DEFAULT 0   -- what cuts could not cover

savings_plan_lines              -- the per-category proposal you reviewed
  savings_plan_id   INTEGER NOT NULL REFERENCES savings_plans(id)
  category_id       INTEGER NOT NULL REFERENCES categories(id)
  baseline_cents    INTEGER NOT NULL   -- average monthly spend
  max_cut_cents     INTEGER NOT NULL   -- how much the nature allows cutting
  proposed_cents    INTEGER NOT NULL   -- the new monthly limit (you can edit it)
  UNIQUE(savings_plan_id, category_id)

dismissed_suggestions           -- cut suggestions you dismissed (milestone 4)
  key           TEXT NOT NULL UNIQUE   -- "recurring:counterparty:12", "big:category:7", "duplicate:<payee>:<amount>"
  title         TEXT NOT NULL

budgets                         -- monthly limit per category; written when a plan is accepted, or by hand
  category_id      INTEGER NOT NULL REFERENCES categories(id)
  month            TEXT NOT NULL   -- YYYY-MM, the first month it applies to (until the category's next row)
  amount_cents     INTEGER NOT NULL CHECK (amount_cents >= 0)
  savings_plan_id  INTEGER NULL REFERENCES savings_plans(id)   -- the plan that wrote it; NULL once set by hand
  removed          INTEGER NOT NULL DEFAULT 0   -- 1: the category has no budget from this month on
  UNIQUE(category_id, month)
```

The monthly savings target lives in `savings_plans`. Named goals with a deadline ("R$ 30 mil for a car by 2027-12") are left for later; they would only add tables. The Nubank RDB is an `investment` account whose balance comes from the "Aplicação/Resgate RDB" transfers.

Design choices:

- **Nothing you imported is hard-deleted.** Accounts and categories are archived. A re-import flags rows that disappeared instead of deleting them. Plans and budgets are yours to delete: deleting a plan can take its budgets with it (back to the limits from before), and removing a budget from a month on writes a `removed` row, so the months before keep their limit and score.
- **Balances and monthly totals are `SUM` queries**, not stored values, so nothing can drift. At household scale (a few thousand rows a year) these take milliseconds even on the Pi.
- **Transfers are recognized even with one side.** The Itaú account and the RDB have no statements, so their transfers have one imported leg (the Pix to your Itaú account and the card's "Pagamento via conta"; the RDB moves). It is still marked `transfer` and never counted as spending or income. The RDB legs are mirrored into the RDB account so its balance is right.

## 7. Import and categorization flow

Details are in [statement-import.md](statement-import.md).

```
 file uploaded
      │
      ▼
 same SHA-256 as before? ──yes──▶ log "duplicate_file", stop
      │ no
      ▼
 parser (pure Ruby, no DB)          Nubank conta CSV │ Nubank cartão CSV │ Itaú cartão PDF
      │
      ▼
 validate: dates, amounts, totals match bill to the cent? ──no──▶ log "rejected", write nothing
      │ yes
      ▼
 ┌───────────── one DB transaction ─────────────┐
 │ upsert by (account, external_id)             │
 │   new        → insert                        │
 │   changed    → update bank fields only       │
 │   missing    → flag, don't delete            │
 │ detect transfers (RDB, fatura, Pix to self)  │
 │ categorize new rows (cascade below)          │
 │ log import with counts                       │
 └──────────────────────────────────────────────┘
      │
      ▼
 review list: uncategorized + suggested, grouped by counterparty
```

Categorization cascade (the first match wins):

```
 transfer between your accounts? ──yes──▶ no category (not spending)
        │ no
 counterparty has a default? ─────yes──▶ that category            (source: rule)
        │ no
 a category_rule matches? ────────yes──▶ rule's category          (source: rule)
   (CNPJ, name, description, amount range)
        │ no
 bank printed a category? ────────yes──▶ mapped category, "suggested" (source: bank)
        │ no
 uncategorized ──▶ review list ──▶ you pick ──▶ "always for this payee?" ──▶ new rule, back-fills past rows
```

## 8. Insights and the savings planner

Everything here is `GROUP BY` queries over categorized transactions plus integer arithmetic. No machine learning, so every number can be traced back to the transactions behind it.

### 8.1 Spending nature

Each expense category carries a `nature`, seeded with sensible defaults that you can change:

| Nature | Meaning | Examples | Planner may cut |
|---|---|---|---|
| fixed | contract or bill you can't trim month to month | financing, health plan, electricity, water, internet/phone | 0% (shown as "renegotiate" ideas instead) |
| essential | needed, but the amount is flexible | groceries, pharmacy, fuel, cooking gas, Pix to people | up to 15% |
| discretionary | wanted, not needed | delivery, restaurants, clothing, online shopping, leisure, parking | up to 50% |

### 8.2 Where the money goes (monthly report)

- Income, spending and **saved** (income − spending) for the month, next to the 3-month average.
- Spending by parent category and category, sorted by size, each with its share of the total and its change vs the 3-month average.
- Top payees (counterparties), and spending split by nature (fixed / essential / discretionary).
- Card installments: how much of each bill is installments, and the month each one ends. Installments can be a large share of a card bill, so this matters.
- International purchases show their IOF and the IOF refund as a pair, so they net to the real cost.

### 8.3 What can I cut (ranked suggestions)

Each signal produces suggestions with an estimated **R$ per month**, sorted by that value. The examples are made up.

| Signal | Rule | Example |
|---|---|---|
| Big discretionary categories | discretionary categories over 5% of spending | online shopping: 20 purchases, R$ 1.500,00 |
| Growth | category this month > 3-month average by 25% and R$ 100 | needs 3 months of data |
| Recurring charges | same payee in 3 of the last 4 months, amount within ±10% | gym, phone, subscriptions, monthly Pix to the same person |
| Many small purchases | 8+ purchases under R$ 50 in a month at similar payees | parking: 12 charges, R$ 130,00 |
| Fees and interest | kind `fee`, or categories under Dívidas | card fee, financing boleto |
| Possible duplicate charge | same payee and amount twice within 2 days | two identical gym charges on the same day (dismiss it if they're two memberships, and it stays quiet) |
| Installments | new installment purchases add to future months | next bill already has R$ 2.000,00 committed |

These are suggestions, not judgments: each can be dismissed, and a dismissed suggestion stays hidden for that payee or category.

### 8.4 "I want to save R$ X a month": the planner

```
 you enter X
     │
     ▼
 baseline = last 3 complete months
   income_avg, spending_avg per category
   saved_today = income_avg − spending_avg
     │
     ▼
 gap = X − saved_today ──── gap ≤ 0 ──▶ "you already save X": suggest moving the extra to RDB
     │ gap > 0
     ▼
 cuttable per category = spending_avg × max_cut_pct   (fixed = 0, essential ≤ 15%, discretionary ≤ 50%)
     │
     ▼
 pool = Σ cuttable ──── pool < gap ──▶ cut everything cuttable, report the shortfall, and list
     │ pool ≥ gap                     the other levers: fixed costs to renegotiate, installments
     ▼                                ending soon (money freed per month)
 split the gap across categories in proportion to "cuttable"
 (Money#allocate, so the cuts add up to the gap exactly)
     │
     ▼
 proposal: for each category  baseline → new limit  (you can edit any line; the
 total updates live, and the plan shows if it still reaches X)
     │ accept
     ▼
 savings_plan saved, and next month's budgets are written from it
```

Small worked example (made-up numbers): income averages R$ 12.000 and spending R$ 10.500, so you save R$ 1.500 today. The target is R$ 3.000, so the gap is R$ 1.500. Discretionary categories average R$ 5.000 (cuttable up to R$ 2.500) and essential ones R$ 4.000 (cuttable up to R$ 600); the remaining R$ 1.500 is fixed and can't be cut. The pool is R$ 3.100, more than the gap. The gap is split 2.500 : 600, so discretionary gives up R$ 1.209,68 and essential R$ 290,32, which add up to exactly R$ 1.500,00 (this exact case is in `spec/unit/tally/money_spec.rb`). The discretionary part is then split across its categories the same way.

### 8.5 Am I on track? (monthly dashboard)

- Target X, saved so far this month, and a **projection**: income so far + expected remaining income − (spent so far + what's left in each budget, or what's already committed to it if more).
- Rows dated after today (installments on a bill exported before it closes) are committed, not spent, until their date: they show as "to come" on their budget line and are left out of the report, the home page, cuts and the planner (`InsightRepo#rows`).
- Each budget line shows spent, limit and **pace** (spent ÷ share of the month elapsed). A category is flagged once it's ahead of pace by more than 10%.
- Card purchases count in the month of the bill they land on (see statement-import.md §5), so the dashboard also shows what's already on the open Itaú bill and the installments committed to the next one.
- At month end, the plan line is scored: target vs actually saved, and which categories went over.
- A month before the plan starts has no target: its budgets were set by hand, so it shows the projection with no "on track" label and no score.

### 8.6 From a number to its rows

Every number should lead to the transactions behind it. The transactions page takes filters in its query string, and `Tally::TransactionFilter` is the one place that reads them and writes them into links, so the filter form, the page links and links from other pages all agree:

| Parameter | Values | Rows |
|---|---|---|
| `account` | account id | that account's |
| `month` | `YYYY-MM` | posted that month |
| `category` | category id, or `none` | that category's, and its children's for a parent; `none` is rows with no category |
| `kind` | `spending`, `income`, `transfer` | spending and income as the report counts them (rows a re-import flagged as missing, and rows dated after today, are left out), so the page's total matches the report; or transfers |
| `nature` | `fixed`, `essential`, `discretionary`, `unset` | whose own category has that nature; `unset` is a category without one, or no category |
| `payee` | `counterparty:12`, `description:padaria exemplo` | paid to that counterparty (all its name variants, see `Tally::Merchants`), or, without one, with that description as the review list groups them (`Tally::Review.key`, also a SQLite function, `tally_payee_key`) |
| `purchase` | id of any installment | every installment of that card purchase, linked the way the installment calendar links them (`Tally::InstallmentCalendar.series`) |

`TransactionRepo` applies a filter to both the page of rows and the totals over all pages. With `kind=spending` the total reads as spending (a positive amount), like the report.

Filters the form has no field for (nature, payee) show as badges above the list, each with a link that drops it.

On the report, each line of the category, nature and payee tables links to its month's rows with `kind=spending`, so the list adds up to the line's amount and row count (a request spec checks every line of every month of the fixtures).

Each purchase on the installments page, and each installment in the report, links to its purchase. With a purchase filter the page also says what is left to pay from this month on (`7 × R$ 120,00 = R$ 840,00`, and the last month): computed from the latest installment's number and amount, since future bills aren't imported. The same figure is the purchase's share of the committed months on the installments page.

## 9. SQLite reliability settings

Set for every connection in `config/providers/db.rb` (milestone 1), and shown on the home page.

| Pragma | Value | Why |
|---|---|---|
| `foreign_keys` | `ON` | Enforce references. |
| `journal_mode` | `WAL` | Readers don't block the writer; safer on crash. |
| `synchronous` | `FULL` | Writes are rare, so pay for durability on an SD card that may lose power. |
| `busy_timeout` | `5000` | Wait instead of failing on concurrent writes. |

Plus a **nightly backup** (`sqlite3 … ".backup"`, 30 copies kept, copied off the SD card), a **weekly `PRAGMA integrity_check`** shown on the home page if it fails, and the original statement files kept in `storage/imports/` so the database can be rebuilt from them.

## 10. Running on the Pi Zero 2 W

- **OS**: Raspberry Pi OS Lite 64-bit (Debian 13 based), whose packaged Ruby should be 3.3; to be confirmed at install. If it's older, install a prebuilt Ruby rather than compiling on 512 MB.
- **Packages**: `sqlite3`, `poppler-utils`.
- **Memory**: target under ~150 MB. Puma single mode, 2 threads, YJIT off, `MALLOC_ARENA_MAX=2`.
- **Service**: systemd unit, restart on failure, start on boot.
- **Access**: LAN only, HTTP basic auth (`BASIC_AUTH_USERNAME` / `BASIC_AUTH_PASSWORD`; in production the app answers 503 until both are set).

## 11. Code layout

```
app/
  actions/      accounts/, transactions/, imports/, review/, reports/, insights/, plans/, budgets/
  operations/   import_statement.rb, categorize.rb, create_rule.rb, pair_transfers.rb,
                build_savings_plan.rb, accept_savings_plan.rb, set_budget.rb
  repos/        account_repo.rb, transaction_repo.rb, import_repo.rb, rule_repo.rb, budget_repo.rb
  relations/ structs/ views/ templates/
lib/tally/
  money.rb
  basic_auth.rb
  importers/    nubank_account_csv.rb, nubank_card_csv.rb, itau_card_pdf.rb
  categorizer.rb
  insights/     baseline.rb, cut_signals.rb, recurring.rb, planner.rb   (pure: data in, numbers out)
  locales.rb    the languages Tally speaks
config/db/migrate/, config/providers/db.rb
bin/                        setup, dev, check-private (pre-commit), reset-db (wipe and reseed a local database)
config/i18n/                pt-BR.yml and en.yml: every word on the pages (§12, milestone 6)
spec/fixtures/statements/   (synthetic only: fake names and amounts in the real formats)
data/                       (gitignored: real statements, the database, rules from your data)
```

Actions validate input and call one operation. Operations hold the rules and the DB transaction. Repos hold queries. `Money` holds all arithmetic. Parsers never touch the database.

## 12. Milestones

1. **Skeleton**: generate the app, SQLite pragmas, `Money` with tests, basic auth, the `accounts` table as the first STRICT table.
2. **Accounts and import**: the accounts, the two Nubank CSV importers and the Itaú PDF importer with golden-file tests on synthetic statements, re-import upsert, import history, transfer detection.
3. **Categorization**: seed categories with nature, generic seed rules (your own rules stay local), review list grouped by payee, rules learned from your choices.
4. **Where the money goes and what to cut**: monthly report, cut suggestions, installment calendar.
5. **Savings planner and budgets**: "save X a month" planner, accepted plan writes budgets, on-track dashboard, month-end score.
6. **Localization**: the app in Brazilian Portuguese (the default) and English. Every page, message and cut suggestion comes from `config/i18n`; amounts, dates and months follow the language (R$ 1.234,56 and 02/09/2026, or R$ 1,234.56 and Sep 2, 2026), and forms read amounts with its decimal mark. Each browser picks its language with a switch in the menu, kept in a cookie; `DEFAULT_LOCALE` sets the default and the language new databases get their starting categories in.
7. **Design and charts**: a dark product look after Linear's (docs/design.md, from the reference in docs/design-linear.app.md): a sidebar grouped by task, charcoal panels with hairline borders, one lavender accent. A home dashboard and charts drawn on the server as inline SVG (no JavaScript bundle, nothing for the Content Security Policy to block): income against spending by month on the home page and the report, spending by category, installments committed per month, and a meter per budget.
8. **Pi deployment** (postponed while the app is tried by hand): systemd, backups, integrity check, memory measurement.
9. **Later**: named savings goals with deadlines, split transactions.
10. **Phase 2, smart suggestions**: local classifier, rule suggestions, unusual-spending alerts, forecasts, optional AI (§15).

## 13. Decisions so far

- Statement sources: Nubank account CSV, Nubank card CSV, Itaú card PDF and Nubank Conta Global CSV.
- The Pi is the single live instance; a laptop is for development.
- The code lives in a public GitHub repository with no personal data in it (§17).
- Each account keeps its own currency and nothing converts between them; the reports are in reais. Conta Global (USD) gets its own report later (issue #22).
- Pix sent to people is its own category, Transferências (Pix), counted as spending.
- Version 1 is deterministic (rules + arithmetic); smart features come later and only suggest.
- Two languages: Brazilian Portuguese (default) and English, with Hanami's built-in i18n. What you type stays as typed: rules, memos and categories you name or rename are data, not translated. Starting categories are named in the default language when a database is seeded, and show in the page's language whichever language seeded them; saving one under its translated name keeps the stored name. Importer diagnostics (a rejected file's reason, parser warnings) are stored with the import as a key and its values (`Tally::Importers::Notice`, JSON in `imports.error` and `imports.warnings`), and the import's page words them in the reader's language, amounts included; imports logged before that kept English text, shown as it is. The command line prints them in English.

## 14. Version 1 is deterministic

Version 1 has **no AI running inside it**. Its "intelligent" parts are plain rules and arithmetic:

| Feature | How it works (deterministic) | Where | Milestone |
|---|---|---|---|
| Parsing 4 sources | CSV reader; poppler `pdftotext -bbox` for Itaú, totals checked to the cent; Conta Global's running balance checked row by row | Ruby importers, golden-file tests | 2 |
| Transfers | Fixed patterns: RDB, Pagamento de fatura, Pix to your own accounts, Conta Global top-ups (matched through the printed rate), Pix no Crédito pair (same ID) | `pair_transfers` operation, `Tally::Exchange` | 2 |
| Categorization | Ordered list of rules on payee/description, then Itaú's printed category mapped, then "Pix to a CPF" → Transferências (Pix) | `category_rules` table, cascade in §7 | 3 |
| Payee clean-up | Strip installment suffix (`\s?\d\d/\d\d$`), merge names that only differ in spaces/punctuation | `counterparties` normalizer | 3 |
| Review list | Group uncategorized rows by payee, biggest total first; "Always use" creates a rule | Same, rule back-fills past rows | 3 |
| Where the money goes | Sums by month, category and nature; card spend counted in the bill's month | `GROUP BY` queries | 4 |
| What to cut | Fixed signals: top discretionary categories; same payee in 3+ months (recurring); 8+ purchases under R$ 50 a month; installments whose last parcel is this month; fees and financing | `insights/cut_signals.rb`, thresholds as settings | 4 |
| Savings planner | Baseline = last 3 months; max cut by nature (0 / 15 / 50%); gap split with largest-remainder `allocate` so it adds up to the cent | `insights/planner.rb` | 5 |
| Import again | Same key → 0 new / 0 changed | Upsert by `(account, external_id)` | 2 |

So for version 1 every number is **calculated, traceable and repeatable**: the same files and rules always give the same result, and every suggestion links to the transactions behind it.

The repository ships only generic seed rules (public merchants by name). Rules written from your own statements (your employer, your utilities, people you pay) are created in your own database, never in seed files (§17).

## 15. Later: smarter features (phase 2, optional)

Only after version 1 is correct and in daily use. Each one only **suggests**; nothing changes data without your click, and the deterministic result stays the source of truth.

| Feature | Approach that fits a Pi Zero 2 W | Needs |
|---|---|---|
| Auto-categorize new payees | Small local text classifier (naive Bayes over payee words, pure Ruby) trained on your own categorized rows; shows "suggested: X (85%)" in Review | a few months of your own categorizations |
| Suggest rules | When you pick the same category for a payee 3 times, offer "always?" automatically | Review history |
| Unusual spending | Flag a category or payee far above its own history (e.g. more than 2× its median) | 6+ months of data |
| Recurring forecast | Predict next month's fixed charges and installments from history | installments + recurring detection |
| Natural-language Q&A or advice | Optional cloud LLM (e.g. Claude API) called from the laptop, sending only aggregated totals, never raw statements; off by default | your explicit opt-in, an API key |

## 16. Status

- **Milestone 1 (skeleton)**: done. Hanami app, SQLite pragmas, `Money`, basic auth, `accounts` table, CI, privacy pre-commit check.
- **Milestone 2 (import)**: done. The three importers with synthetic golden files (and an optional local check against real statements in `data/statements/`), upsert by `(account, external_id)`, import history, transfer pairing with mirror rows for Itaú conta and Nubank RDB, "This is me" for Pix to yourself, import / accounts / transactions / counterparties pages, and `rake tally:import[...]`.
- **Milestone 3 (categorization)**: done. 52 seed categories with nature and maximum cut, generic seed rules for public merchants (`lib/tally/categories.rb`), the categorizer (counterparty default, rules, Itaú's category as a suggestion), Pix to people as Transferências (Pix), the review list grouped by payee with "always" (counterparty default or learned rule), per-transaction category and memo, categories and rules pages. Your own rules go in your database, or in a gitignored `data/seeds.rb`.
- **Milestone 4 (where the money goes and what to cut)**: done. Monthly report (income, spending, saved against the 3-month average; by category, nature and payee; the month's installments), cut suggestions for the seven signals of §8.3 with dismissals (`dismissed_suggestions` table), and the installment calendar from each purchase's latest installment, next to what Itaú prints as committed. Installments are linked into purchases in bill order, so several paid early on one bill (Nubank's "Desconto Antecipação") end the purchase instead of looking like new ones. Installments after the first are left out of "big", "growth", "recurring" and "duplicate": they are already committed and repeat by design. New installment purchases are one suggestion per month.
- **Milestone 5 (savings planner and budgets)**: done. The "save X a month" planner over the last three complete months (`Tally::Planner`, with the worked example of §8.4 as a test), a draft you edit line by line with a live total, accepting writes the budgets from its first month and replaces the previous plan, the on-track dashboard with pace and projection (`Tally::BudgetMonth`), editable limits, and month-end scores. A budget row applies from its month until the category's next row. Plans can be deleted, with or without the budgets they wrote, and budgets removed from a month on, one category or all (issue #15). The plan and budget pages explain the four steps from a plan to budgets and mark the one you are on (`PlanRepo#step`, `plans/_flow`); an accepted plan links to the budgets it wrote and back (issue #16).
- **Milestone 6 (localization)**: done. Brazilian Portuguese and English for every page, form error and cut suggestion (`config/i18n`, with a spec that keeps both files in step), a language switch in the menu remembered per browser, locale-aware amounts, dates and months, form amounts read with the language's decimal mark, and starting categories named in the default language (`DEFAULT_LOCALE`). Cut suggestions and bill checks now carry facts instead of English sentences, so the page words them.
- **Milestone 7 (design and charts)**: done. The stylesheet in `public/assets/app.css` (served by `Actions::Assets::Show`, like the planner's script), a sidebar layout that folds into a top bar on phones, the home dashboard, and `Tally::Charts` for the column charts. Every chart sits next to a table with the same numbers, and each mark shows its value on hover.
- **Conta Global import** (issue #22, first part): done. The dollar account's CSV (`Importers::ContaGlobalCSV`), checked row by row against its running balance; card purchases and refunds in dollars with the foreign amount, rate and fee in their own columns; top-ups paired with Nubank conta's conversion through the rate (`Tally::Exchange`); dollar rows kept out of every BRL total and shown in US$. Still to do: the account's own report.
- **Counterparty names** (issue #37): done. Each counterparty can have your own display name and a note (`/counterparties/:id`, also linked from a transaction and a review group). Every list shows the display name (`Tally::DB::Repo.counterparty_label`), with the bank's name kept underneath and in tooltips; the counterparties search matches either. Imports, matching (`match_key`), merchant grouping and rules keep using the bank's name.
- **Next, milestone 8 (Pi deployment)**, postponed while the app is tried by hand.

## 17. Public repository: keeping personal data out

The repository is public, so nothing personal is committed.

- **Test fixtures are synthetic.** Small generated files mimic each format exactly: Nubank account CSV, Nubank card CSV and an Itaú bill PDF. They have fake names ("Maria Exemplo"), fake CPF/CNPJ, invented merchants and amounts, and totals that add up. A script in `spec/support/` builds them, so the real layout quirks (split words in the Itaú PDF, `"- 7,06"` negatives, repeated IDs) are reproduced on purpose.
- **Real statements never enter git.** They live in `data/` (gitignored) along with the SQLite database and backups. An optional local check runs the importers on them and compares totals, but it is skipped when `data/` is empty (CI and anyone else).
- **Seed data is generic.** The repo ships default categories and rules for public merchants (iFood, Uber, Amazon, utilities by name). Rules that name people, your employer, your company or your CPF/CNPJ are created in your own database, never in seed files.
- **Docs and examples use fake numbers.**
- **Guard rails:** `.gitignore` for `data/`, databases, and `*.csv` / `*.pdf` outside `spec/fixtures/`, plus `bin/check-private`, a pre-commit hook (installed by `bin/setup`) that rejects staged files matching the patterns you keep in the gitignored `data/private-patterns.txt` (your CPF, account numbers, names).

## Sources

- Hanakai: https://hanakai.org/ and https://hanakai.org/learn/hanami (guides for Hanami v3.0)
- Database configuration: https://hanakai.org/learn/hanami/v3.0/database/configuration
- Migrations: https://hanakai.org/learn/hanami/v3.0/database/migrations
- Operations: https://hanakai.org/learn/hanami/v3.0/operations
- Gem versions and Ruby requirement: rubygems.org API for `hanami`, `hanami-db`, `hanami-cli`, `rom`, `rom-sql`, `dry-operation`, `sqlite3`
