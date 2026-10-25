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
7. **One currency per account.** Amounts are stored in their account's currency (`accounts.currency`): BRL everywhere except Nubank Conta Global, in USD. Nothing converts between them. The report, cuts, budgets and the category and counterparty totals count only BRL accounts; a list over several currencies shows a total per currency. A dollar account has its own report in dollars; the only conversion is an estimate shown beside it, at what its top-ups cost (§16).

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
  name                  TEXT NOT NULL UNIQUE      -- "Nubank conta", "Nubank cartão", "Itaú cartão", "Nubank RDB", "Itaú conta"; someone else's: "Nubank conta (Bruno)"
  template              TEXT NULL      -- its kind among Importers::ACCOUNTS ("Nubank conta"), what the importers look it up by (issue #21)
  person_id             INTEGER NULL REFERENCES people(id)   -- whose account it is (§6.1); the app always sets it
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
  is_self         INTEGER NOT NULL DEFAULT 0     -- someone of the household (you at another bank, your partner) → transfer
  person_id       INTEGER NULL REFERENCES people(id)   -- who of the household, when is_self is 1 (§6.1)
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

transaction_adjustments         -- what you know about a row that its statement doesn't say (issue #14)
purchase_adjustments            -- one adjustment for every installment of a card purchase (issue #69)
  transaction_id         INTEGER NOT NULL UNIQUE REFERENCES transactions(id)
  kind                   TEXT NOT NULL   -- canceled | reimbursed | amount_changed
  amount_cents           INTEGER NULL    -- reimbursed: what came back (> 0); amount_changed: the real amount, signed like the row
  refund_transaction_id  INTEGER NULL UNIQUE REFERENCES transactions(id)   -- reimbursed by an imported row (a Pix back, a card refund)
  note                   TEXT NULL

people                          -- the household (issue #21): the first is you, named "Eu" until you rename yourself
  name            TEXT NOT NULL UNIQUE

subscription_marks              -- payees you said are or aren't subscriptions, by payee key (issue #74)
trips, trip_accounts, trip_rows -- a trip's dates, accounts and the rows you added or took out (issue #75)
home_bills                      -- a household bill: name, category, expected amount, due day, payee by match key (issue #113)
home_bill_payments              -- one per bill and month: paid on, amount, who paid; linked rows by (account name, external_id)
home_bill_receipts              -- receipt files in storage/receipts/<sha256>: hash, type, size, name, bill-month
```

The monthly savings target lives in `savings_plans`. Named goals with a deadline ("R$ 30 mil for a car by 2027-12") are left for later; they would only add tables. The Nubank RDB is an `investment` account whose balance comes from the "Aplicação/Resgate RDB" transfers.

Design choices:

- **Nothing you imported is hard-deleted.** Accounts and categories are archived. A re-import flags rows that disappeared instead of deleting them. Plans and budgets are yours to delete: deleting a plan can take its budgets with it (back to the limits from before), and removing a budget from a month on writes a `removed` row, so the months before keep their limit and score.
- **Your corrections live beside the imported row, never in it.** A row canceled, reimbursed or charged another amount keeps its statement amount; its `transaction_adjustments` row says what it counts as (`Tally::Adjustments.counted_amount`). Re-imports update the row by `(account, external_id)` and never touch the adjustment. The report, cuts, budgets, planner, installment calendar and the spending and income filters on the transactions page count rows that way: a canceled or fully reimbursed row counts as nothing, and a refund row linked to a purchase counts inside it, not on its own. The transactions list shows a badge, the statement's amount struck through, and what the row counts as. Category and counterparty totals still show the statement amounts.
- **A whole card purchase can be adjusted at once** (issue #69). From an installment's page, "every installment of this purchase" saves a `purchase_adjustments` row and one `transaction_adjustments` row per installment, linked to it. Canceled zeroes them all; reimbursed and amount changed take the whole purchase's amount and split it over the installments in proportion to each (`Tally::Adjustments.purchase_shares`, unimported ones weighing as much as the latest), so the rounding cents stay where the bank put them. Installments are found like the installment calendar finds them (card, merchant, count, bill order), not by the bank's purchase key, so a first installment with rounding cents is included. Every import adjusts installments newer than `through_transaction_id` (`AdjustPurchase#catch_up`). Removing it from the purchase removes every installment's adjustment; removing one installment's leaves the rest, and that one is not adjusted again.
- **Balances and monthly totals are `SUM` queries**, not stored values, so nothing can drift. At household scale (a few thousand rows a year) these take milliseconds even on the Pi.
- **Transfers are recognized even with one side.** The Itaú account and the RDB have no statements, so their transfers have one imported leg (the Pix to your Itaú account and the card's "Pagamento via conta"; the RDB moves). It is still marked `transfer` and never counted as spending or income. The RDB legs are mirrored into the RDB account so its balance is right.

### 6.1 The household

Tally keeps a second person's statements beside yours (issue #21). The accounts page lists the `people` of the household and adds one; the import form (and `rake 'tally:import[files,Name]'`) asks whose statements a file holds, and that person's accounts are their own rows in `accounts`, named after them ("Nubank conta (Bruno)") and found by `(template, person_id)`. Your accounts keep their plain names, so nothing changes for a household of one.

- **Marking people.** The counterparties page marks a name as someone of the household: "This is me" with one person, a choice of who with more (`counterparties.person_id`). A Pix to or from them becomes a transfer, as a Pix to yourself always has. Its other side is that person's account at the bank the row names (`Importers.account_at`: Itaú or Nubank), when it is imported; an Itaú conta has no statement, so it is created and mirrored, as yours is (`AccountRepo#counter_account_id`).
- **Pairing.** Both sides imported, the Pix pairs like a card payment (`PairTransfers`), whatever order the files and marks came in: a transfer that pointed at no account finds it once the other person's statement is in. A transfer between two people with no pair is **unmatched** (`/transactions?kind=unmatched`): the other person's statement for that month is missing, or their account isn't imported. It still never counts as spending.
- **The person switch.** Home, Report, Cuts and Budgets add up the whole household by default, and a switch above them (`shared/_person_switch`, shown with more than one person) narrows them to one person's accounts (`?person=`, `InsightRepo#rows(person:)`). Every link from those pages to the rows behind a number keeps the person (`TransactionFilter#person`). Transfers between the two count in no view, so the household's figures are the sum of each person's, and a shared payee (both pay the same supermarket) is one line in the household view, as counterparties are shared. Budgets and the plan are the household's: one person's view shows their spending against the same limits, without the plan's target. Home and Report warn while any transfer between people is unmatched.
- **The default until then.** Until you add someone and mark their name, a Pix to your partner is a Pix to a person: spending, in Transferências (Pix), as before. Marking them is the switch: from then on it is a transfer in every view, yours included, so your own spending no longer has money you only moved to them (in the issue's example, your view shows R$ 3.800, not R$ 4.000).

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
| `trip` | trip id | the trip's rows, as its page counts them (`Tally::Trip`) |

`TransactionRepo` applies a filter to both the page of rows and the totals over all pages. With `kind=spending` the total reads as spending (a positive amount), like the report.

Filters the form has no field for (nature, payee) show as badges above the list, each with a link that drops it.

On the report, each line of the category, nature and payee tables links to its month's rows with `kind=spending`, so the list adds up to the line's amount and row count (a request spec checks every line of every month of the fixtures).

Each purchase on the installments page, and each installment in the report, links to its purchase. With a purchase filter the page also says what is left to pay from this month on (`7 × R$ 120,00 = R$ 840,00`, and the last month): computed from the latest installment's number and amount, since future bills aren't imported. The same figure is the purchase's share of the committed months on the installments page.

**The way back (issue #87).** Pages below a section show a breadcrumb above their title (`shared/_breadcrumb`): `Viagens › Praia`. A link from one page to a list of rows or to a row's page carries the page it came from as `back` (the `transactions_path`, `transaction_path` and `with_back` view helpers), which `Tally::Action#back_param` only accepts as a local path. The transactions list keeps `back` in its filter form, page links and category changes; a row's page keeps it through its forms, so saving doesn't lose the way back. The crumb is named after that page, a filtered list by its search, category and month (`Lançamentos (Delivery, jul/2026)`). Without a valid `back`, the crumb is the page's section: Contas for an account report, Viagens for a trip, Cortes for subscriptions.

### 8.7 Subscriptions and recurring charges

`/subscriptions` (issue #74, `Tally::Subscriptions`) lists charges that repeat every month, from two years of `InsightRepo#rows` up to the latest month that is over. A payee (`Insights.payee_key`, so a card merchant and its Pix or boleto payments are one counterparty) is a subscription when, in some 4 months in a row, it charged in at least 3, each month's total within ±10% of their median; the latest may be a price increase (below), so three charges with a rise still count. Rows count as adjusted (§6), so a canceled charge doesn't keep one alive.

- A foreign charge counts together with its IOF row, which carries the same merchant, so the rate moving month to month doesn't break the match. Fees without a merchant (the card's own fee) and installments are left out.
- Each row shows the payee (linked to its rows with `kind=spending&payee=…`), category, accounts, last charge and its date, cost per month (the last charge) and per year (×12), and the first month seen.
- A **price increase** is flagged on any rise of a fixed price (the two charges before were equal), or a rise over 10% on one that varies. A subscription with no charge for 2 months is **stopped** and left out of the totals at the top.
- "Not a subscription" on a row, or "It's a subscription" on a counterparty's page, is kept in `subscription_marks` by payee key, so re-imports keep it; the page lists them with an undo. The cuts page links here; its "recurring" signal stays as it was.

### 8.8 Trips

`/trips` (issue #75, `Tally::Trip`) adds up a trip as one total across accounts. A trip has a name, a first and last day, and the accounts to look in (`trip_accounts`; none means all).

- Its rows are the spending rows bought between its dates (an installment's purchase date, else the posting date) in those accounts, plus the rows you added from any date, minus the ones you took out (`trip_rows`, `included` 1 or 0, kept apart from the rows so re-imports keep them). Rows are added or taken out from a row's page, and taken out or put back on the trip's page.
- A card purchase in installments is in or out as a whole: in when any installment is, out when you took any out. Installments not on a bill yet count too, at the latest one's amount (`InstallmentCalendar::Purchase`).
- IOF rows (their description says IOF) are in the total and also shown as their own line, net of IOF given back.
- Rows in another currency (Conta Global) show in their currency and count in reais at the average cost of their account's top-ups up to the end of the trip's last month (`Tally::TopUps`, as the account report does). Without a paired top-up they stay out of the total, and the page says so. Top-ups are transfers and never count.
- The page shows the total, the foreign subtotal with its reais, by category (top level) and by account, each linked to `/transactions?trip=…` with that category or account, and the rows.
- Trip rows still count in the monthly report; `/report?trips=hide` leaves every trip's rows out (`InsightRepo#rows(without:)`) to see a normal month.
- **Map** (issue #144, `Tally::Places`, `Charts.map`): `/trips` shows a dot per place of every trip, a trip's page only its own. A row's place is the Itaú card's city (`transactions.location`), else, for a row in another currency (Conta Global), the last one to three words of the merchant ("Loja Exemplo TORONTO"); Nubank rows have none and are skipped. The text is folded (`Tally::Search.fold`) and matched against `config/places.yml` (Natural Earth 1:10m populated places, public domain: every Brazilian city, elsewhere capitals and cities of 100,000+, with their other-language names as aliases, biggest first so a shared name is the biggest city), exactly, or as the start of a name when it has 8+ characters (Itaú cuts cities at about 13: "RIO DE JANEIR"), also with accented letters dropped ("So Paulo"). Text that matches nothing is listed under the map. The world is `public/assets/world.svg` (Natural Earth 1:110m countries, x = lon + 180, y = 90 - lat), served cached for a week and drawn with `<use>`, so the page carries only the dots; the `viewBox` zooms to the places at 2:1. No JavaScript, no map service. A city the map misses goes into `config/places.yml` (public coordinates only).

### 8.9 Home bills

`/home-bills` (issue #113, `Tally::HomeBills`) tracks fixed household bills: rent, energy, water, internet, condo fee, car or mortgage payments. A bill (`home_bills`) has a name, an optional category and expected amount, a due day (1-31, clamped to the month's last day) and optionally a payee, set when it is added from a subscription ("Track as home bill" on `/subscriptions` fills in the form).

- Each month is **paid** once it has a payment (`home_bill_payments`, one per bill and month), else **due** up to its due day and **late** after it. The list shows the month before and this one; a bill's page shows both with their payment, receipts and forms.
- A payment is either **linked** to an imported row or entered **by hand** (day, amount, who paid). A link keeps the row's account name and bank `external_id` (the re-import upsert key, §7), never its `id`, so it finds the row again after a re-import or a reset. Who paid is a person of the household (#125), kept by name so a reset keeps it: a linked row's account owner, or whoever is picked by hand (you when the household is only you). Renaming a person renames them on past payments; a name typed before #125 that matches no one stays as typed.
- The bill's page **suggests** the row: the payee's spending row nearest the due day (±15 days); without a payee, a row of its category within 20% of the expected amount. You confirm it, or pick another from the searchable picker of every spending row near the due day.
- A payee is kept by its counterparty's `match_key` (`match:…`), not the counterparty id, which a reset changes.
- **Receipts** (`Tally::Receipts`, `home_bill_receipts`): photos or PDFs of a boleto or Pix, any number per bill-month. JPEG, PNG and PDF only, told apart by their first bytes, up to 10 MB. Files go to `RECEIPT_STORAGE_DIR` (`storage/receipts/`, gitignored), named by their SHA-256 (written to a temporary file, then renamed), so the same file is kept once; the table keeps the hash, type, size, original name, month and upload time. They are served only by `/receipts/:id` (behind the login, with `send_file`, cached for a year since files never change), never from `public/`. Deleting the last row that uses a file deletes the file.
- `bin/reset-db` keeps home bills: after recreating the database it copies the three tables back from its backup (`Tally::HomeBillsCopy`, a category found again by its name and its parent's), and never touches `storage/`.
- Backups: the database as today, plus the receipts folder (rsync it daily alongside the database backup).

## 9. SQLite reliability settings

Set for every connection in `config/providers/db.rb` (milestone 1), and shown on the home page.

| Pragma | Value | Why |
|---|---|---|
| `foreign_keys` | `ON` | Enforce references. |
| `journal_mode` | `WAL` | Readers don't block the writer; safer on crash. |
| `synchronous` | `FULL` | Writes are rare, so pay for durability on an SD card that may lose power. |
| `busy_timeout` | `5000` | Wait instead of failing on concurrent writes. |

Plus a **nightly backup** (`sqlite3 … ".backup"`, the newest 5 kept, copied off the SD card), a **`PRAGMA integrity_check`** on every copy, shown on the Debug info page and the home page if it fails or the newest copy is old, and the original statement files kept in `storage/imports/` so the database can be rebuilt from them. Home bill receipts live in `storage/receipts/` (§8.9) and are copied off daily with rsync.

## 10. Running on the Pi Zero 2 W

The Pi is headless and reached only over SSH. Deploys go from the laptop with plain `ssh`, `git archive` and `rsync`: the Pi needs no GitHub access, Docker or Kamal (Kamal needs Docker and kamal-proxy, too much for 512 MB; it fits the VPS route in issue #103). The Pi can share the board with other small services (Pi-hole, for one, which keeps port 80).

- **OS**: Raspberry Pi OS Lite 64-bit. Debian 12 (Bookworm) is fine: it has security updates under Debian LTS until mid-2028. Its packaged Ruby (3.1) is too old, so Ruby comes from [mise](https://mise.jdx.dev). Raspberry Pi doesn't support upgrading Pi OS in place; to move to a newer one, reflash, then run `bin/pi-setup` and `bin/deploy` again and copy the database back.
- **Packages**: `sqlite3`, `poppler-utils`, and the headers Ruby builds with.
- **Memory**: target under ~150 MB. Puma single mode, 2 threads, YJIT off, `MALLOC_ARENA_MAX=2`; the service is capped at 250 MB (`MemoryMax`) so SSH and the other services keep room.
- **Service**: systemd unit `tally`, restart on failure, start on boot, logs in the journal (`sudo journalctl -u tally`).
- **Name**: the `tally-name` unit announces `tally.local` over mDNS with Avahi (`avahi-publish -a -R`, the Pi's first address), so the address doesn't depend on the Pi's hostname. It keeps a port: port 80 belongs to Pi-hole, and sharing it would take a reverse proxy, which isn't worth it on this board. It isn't a Pi-hole Local DNS record because that only works when the router hands out Pi-hole as the DNS server, and Apple devices look up `.local` names only over mDNS. `.local` lookups work on macOS and iOS but are unreliable on Android and Windows. After the Pi's address changes: `sudo systemctl restart tally-name`.
- **Access**: LAN only, at `http://tally.local:2300` (or `http://<pi>:2300`), optional HTTP basic auth (`BASIC_AUTH_USERNAME` / `BASIC_AUTH_PASSWORD`; both empty means no login in any environment, with a warning logged at boot in production, and only one set answers 503).

### 10.1 Layout on the Pi

```
~/tally/
  releases/<commit>/   one folder per deployed commit (the last three are kept)
  current ─▶ releases/<commit>   what the service runs
  shared/
    db/tally.sqlite    the live database
    storage/           imports/ and receipts/ (§8.9)
    backups/           nightly-*.sqlite and pre-deploy-*.sqlite, the newest 5 of each, and log.jsonl (one line per run)
    bundle/            installed gems, shared by the releases
  tally.env            production settings (HANAMI_ENV, port, paths, basic auth); written once, yours to edit
  ruby.env             PATH to mise's Ruby and the Bundler settings; rewritten by setup
```

### 10.2 Scripts (run on the laptop)

| Command | What it does |
|---|---|
| `bin/pi-setup [user@host]` | Once, and after a reflash or to change Ruby. Copies `deploy/pi/` to the Pi and runs `setup.sh`: apt packages, mise and Ruby (`TALLY_RUBY`, default 4.0; mise downloads a precompiled build, about a minute; without one it compiles on the Pi for about an hour), the folders and settings above, the `tally` service, the `tally-backup` timer and the `tally-name` service (`TALLY_NAME`, default `tally`; empty removes it). Safe to run again. |
| `bin/deploy [user@host]` | Each release. Sends the committed HEAD with `git archive` (uncommitted changes and gitignored files never leave the laptop) and runs `deploy/pi/release.sh` from it: `bundle install`, a pre-deploy backup, `hanami db migrate` (or `db prepare` the first time, which seeds), switches `current`, restarts the service and waits for it to answer. |
| `bin/pull-backup [user@host]` | Copies `shared/backups/` and `shared/storage/` off the SD card into `data/pi/` (gitignored). Nothing is deleted on either side. |

The host defaults to `$TALLY_HOST`, else `pi@pihole.local`. The Pi user needs passwordless sudo (Pi OS's first user has it) and the laptop's SSH key (`ssh-copy-id`).

### 10.3 Backups

`tally-backup.timer` runs `deploy/pi/backup.sh` at 03:30 (or at boot if the Pi was off): SQLite's online `.backup`, then `PRAGMA integrity_check` on the copy, keeping the newest 5 of each kind (`TALLY_BACKUP_KEEP` in `tally.env` changes it). A failed check fails the unit (`systemctl --failed`). Each deploy takes a `pre-deploy` copy before migrating. Off the SD card they go with `bin/pull-backup`, along with the receipts and imported files.

Each run also appends one JSON line to `backups/log.jsonl` (UTC time, kind, file, size, and `ok` or what went wrong; the last 100 lines kept). A copy that fails the backup or the check is deleted, so the folder only holds good copies. The app finds the folder through `BACKUP_DIR` (`setup.sh` writes it into `tally.env`, adding it to an older one) and reads it with `Tally::Backups` (issue #137): the **Backups** section of the Debug info page (`/debug#backups`, next to the export) shows the last run and its check, and the copies newest first with their kind, time and size. When the last run failed, or the newest copy is older than 36 hours (or there is none), that section and the home page show a warning linking there. Downloading a copy (`GET /debug/backups/<file>`, only names the folder lists) follows the export rule below, the same switch as the export button (`Tally::DatabaseExport.allowed?`), otherwise 403. Nothing runs in the background: the section lists one folder and reads a 100-line file. With `BACKUP_DIR` blank (development) the section explains how backups work on the Pi and home shows nothing.

A copy can also be downloaded from the browser: **Download the database** on the Debug info page (`/debug`, issue #136) runs `VACUUM INTO` a temp file (a consistent snapshot even mid-write in WAL mode), checks it with `PRAGMA integrity_check` and sends it as `tally-YYYYMMDD-HHMMSS.sqlite` in local time (`Tally::DatabaseExport`). Only the database, not `storage/`. The file holds every transaction, so the button shows and `POST /debug/export` answers only when basic auth is on (both `BASIC_AUTH_*` set) or `ALLOW_EXPORT_WITHOUT_LOGIN=true` (`Tally::DatabaseExport.allowed?`); otherwise the page says why and the route answers 403. Loading a file back from the browser is #139.

To restore: `sudo systemctl stop tally`, copy the backup over `shared/db/tally.sqlite` (removing `tally.sqlite-wal` and `-shm`), `sudo systemctl start tally`. Moving the laptop's database to the Pi the first time is the same, with a copy made by `sqlite3 db/tally.sqlite ".backup /tmp/tally.sqlite"` and `rsync -a storage/ <pi>:tally/shared/storage/` for the files.

## 11. Code layout

```
app/
  actions/      accounts/, transactions/, imports/, review/, reports/, insights/, plans/, budgets/
  operations/   import_statement.rb, categorize.rb, create_rule.rb, pair_transfers.rb,
                build_savings_plan.rb, accept_savings_plan.rb, set_budget.rb
  repos/        account_repo.rb, transaction_repo.rb (+ transaction_repo/ writing.rb, transfers.rb), import_repo.rb, rule_repo.rb, budget_repo.rb
  relations/ structs/ views/ templates/
lib/tally/
  money.rb
  basic_auth.rb
  importers/    nubank_account_csv.rb, nubank_card_csv.rb, conta_global_csv.rb,
                itau_card_pdf.rb + itau_card_pdf/ (layout.rb, reader.rb, bill.rb)
  categorizer.rb
  insights/     baseline.rb, cut_signals.rb, recurring.rb, planner.rb   (pure: data in, numbers out)
  locales.rb    the languages Tally speaks
config/db/migrate/, config/providers/db.rb
bin/                        setup, dev, check-private (pre-commit), reset-db (wipe and reseed a local database),
                            pi-setup, deploy, pull-backup (§10)
deploy/pi/                  what runs on the Pi: setup.sh, release.sh, backup.sh, publish-name.sh, systemd units
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
8. **Pi deployment**: deploys over SSH, systemd, nightly backups with an integrity check, memory measurement (§10).
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
| Category from the table | A row's category cell on /transactions is a picker that saves on change; ticked rows get one category at once. Manual, no rule; back to the same filters and page (issue #83) | `transactions.recategorize`, `operations.assign_category` | 3 |
| Searchable pickers | Every `<select data-picker>` (category pickers everywhere, account and month filters) gets a text box that narrows the options as you type, accents and case ignored, matching a category's parent too; the `<select>` stays in the form, so it works without JS (issue #84) | `public/assets/picker.js` | 3 |
| Search and bulk categorize | A search box on /transactions (`q`, one more TransactionFilter param): a whole amount (`45,90`, `R$ 45,90`, `-45,90`) matches the row's amount, as imported or adjusted, either sign unless typed; text matches every word, accents and case folded, across description, bank description, memo, adjustment note and counterparty name, display name and note. "Select all N results" changes the category of every row the filters find on every page, transfers skipped, refused with no filter (issue #85) | `TransactionRepo#search`, `Tally::Search.amount`, `transactions.recategorize` | 3 |
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
- **Milestone 7 (design and charts)**: done. The stylesheet in `public/assets/app.css` (served by `Actions::Assets::Show`, like the planner's script), a sidebar layout that folds into a top bar on phones, the home dashboard, and `Tally::Charts` for the column charts. Every chart sits next to a table with the same numbers, and each mark shows its value on hover. Later (#110): a light theme with a switch (cookie, else the system's setting), sidebar groups that fold, and a Debug info page (`/debug`) with the SQLite settings in effect, moved off the home page.
- **Conta Global import** (issue #22, first part): done. The dollar account's CSV (`Importers::ContaGlobalCSV`), checked row by row against its running balance; card purchases and refunds in dollars with the foreign amount, rate and fee in their own columns; top-ups paired with Nubank conta's conversion through the rate (`Tally::Exchange`); dollar rows kept out of every BRL total and shown in US$.
- **Account report** (issue #22, second part): done. `/accounts/:id/report` is one account's report in its own currency (`InsightRepo#rows(account_id:)` through `Tally::Report`): spending by category, by month (with a chart) and by payee, each linked to its rows. A foreign-currency account also lists the month's top-ups with the reais their paired leg paid and the rate, and converts the month's spending to reais at the average cost of every top-up so far (`Tally::TopUps`, exact rationals, IOF and spread included). Nothing is added to the main report, which links to these pages; the accounts page links to every account's report.
- **Adjusting a transaction** (issue #14): done. From a row's page, mark it canceled, reimbursed (an amount you type, or an imported row that paid it back) or with another amount, with a note; or remove the adjustment. Kept in `transaction_adjustments`, so re-imports keep it (§6). Every installment of a card purchase can be adjusted at once (issue #69, §6).
- **Counterparty names** (issue #37): done. Each counterparty can have your own display name and a note (`/counterparties/:id`, also linked from a transaction and a review group). Every list shows the display name (`Tally::DB::Repo.counterparty_label`), with the bank's name kept underneath and in tooltips; the counterparties search matches either. Imports, matching (`match_key`), merchant grouping and rules keep using the bank's name.
- **Subscriptions** (issue #74): done. See §8.7.
- **Trips** (issue #75): done. See §8.8.
- **Home bills** (issue #113): done. See §8.9.
- **Household** (issue #21): people, accounts by owner, Pix between people paired or shown as unmatched, and the household / person switch (§6.1).
- **Milestone 8 (Pi deployment)**: in progress (issue #23). `bin/pi-setup`, `bin/deploy`, `bin/pull-backup`, the `tally` service and the nightly backup with an integrity check, a database download on the Debug info page (#136), and a Backups section there with a home warning for a failed or old backup (#137) (§10). Left: measuring memory and response times on the Zero 2 W with real-sized data.

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
