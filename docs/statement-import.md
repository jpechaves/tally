# Statement Import and Categorization

How Tally reads bank statements, re-imports them safely and categorizes the rows. Companion to [architecture.md](architecture.md).

> Every name, document number and amount below is made up. The formats and quirks are real; the data is not (architecture.md §17).

## 1. Sources

| Source | File | One file covers |
|---|---|---|
| Nubank account (conta) | CSV export, named like `NU_<account>_01JUN2026_30JUN2026.csv` | a date range, usually a month |
| Nubank credit card | CSV bill export, named like `Nubank_2026-07-09.csv` (the due date) | one bill |
| Itaú credit card | PDF bill (fatura), a cover page with the summary and boleto, then transactions in columns | one bill |

How the money moves: the salary arrives in the Nubank account; a Pix sends the Itaú bill amount to the Itaú account, which pays the Itaú card; the Nubank account also pays the Nubank card bill.

| Account | Kind | Imported? | How it appears |
|---|---|---|---|
| Nubank conta | checking, salary lands here | yes, CSV (§2) | every row |
| Itaú cartão | credit card | yes, PDF bills (§3) | every purchase, fee and refund |
| Itaú conta | checking, only used to pay the Itaú card | no | the Pix in and the bill payment out, both transfers |
| Nubank RDB | savings | no file needed | balance built from "Aplicação/Resgate RDB" rows |
| Nubank cartão | credit card | yes, CSV bill export (§2b) | every purchase, installment, IOF, refund and discount |

**The Itaú account is a pass-through.** The Pix sent to it matches the bill it pays within cents, give or take a small amount already sitting in the account. So the importer marks the Pix to the Itaú account as a transfer to "Itaú conta", and the card's "Pagamento via conta" as a transfer from it. The Itaú account's balance is just the running sum of the two, which stays close to zero. A difference above a threshold (a setting, default R$ 50) shows up as a warning on the import page rather than as spending.

**The Nubank card is fully itemized.** The Nubank account CSV only shows the bill payment; the card's purchases come from the separate card bill exports (§2b). With both imported, "Pagamento de fatura" in the account and "Pagamento recebido" on the card pair up as one transfer, so nothing is counted twice.

## 2. Nubank account CSV

Format (example row with fake data):

```
Data,Valor,Identificador,Descrição
08/06/2026,-187.43,0b6f3a52-1d2e-4c8f-9a7b-5e4d3c2b1a00,Transferência enviada pelo Pix - ENERGIA EXEMPLO S.A. - 12.345.678/0001-00 - BANCO EXEMPLO S.A. (0001) Agência: 1234 Conta: 56789-0
```

- UTF-8, comma-separated, header row, no BOM. Parse with Ruby's `CSV` (handles quoting if a description ever contains a comma).
- `Data` is `DD/MM/YYYY`. `Valor` uses a dot as the decimal separator and is signed (negative = money out). Parse with `Money.parse(valor, decimal: ".")`, which requires at most 2 decimals.
- `Identificador` is a UUID, and **almost** unique: a Pix paid with the credit card ("Pix no Crédito") produces two rows with the same UUID, `+X` "Valor adicionado na conta por cartão de crédito" and `-X` for the Pix itself. So the upsert key is `Identificador + ":" + sign`, and the importer rejects a file where that pair still repeats instead of silently merging rows.
- The period is in the file name (`01JUN2026_30JUN2026`, Portuguese month abbreviations: JAN FEV MAR ABR MAI JUN JUL AGO SET OUT NOV DEZ).
- The file has no running balance, so there is nothing in the file to check the parsed totals against. Instead, you can type the account's closing balance once, and the app shows any difference.

`Descrição` is parsed into structured fields with an ordered list of patterns:

| Pattern (prefix) | kind | What we extract |
|---|---|---|
| `Transferência enviada pelo Pix - NAME - DOC - BANK (CODE) Agência: A Conta: C` | purchase, or transfer if the counterparty is you | counterparty name, CPF/CNPJ, bank, branch, account |
| `Transferência recebida pelo Pix - …` / `Transferência Recebida - …` | income or refund, or transfer | same fields |
| `Pagamento de boleto efetuado - NAME` | bill_payment | counterparty name (truncated by the bank, e.g. "FINANCEIRA EXEMPLO SOCIEDADE DE CREDITO") |
| `Pagamento de fatura` | transfer → Nubank cartão (pairs with the card's "Pagamento recebido") | none |
| `Valor adicionado na conta por cartão de crédito - Valor adicionado para Pix no Crédito` + the Pix with the same UUID | transfer pair (card → account → payee) | the spending is counted once, on the card's `Pix no Crédito - NAME` row (the Pix amount plus the card fee), so both account rows are marked as pass-through |
| `Conversão para Conta Global` | transfer → Nubank Conta Global (dollar account, balance only) | none |
| `Aplicação RDB` / `Resgate RDB` | transfer → / ← Nubank RDB account | none |
| `Compra no débito via NuPay - MERCHANT` | purchase | merchant |
| anything else | purchase / income by sign, flagged "unparsed description" | raw text kept |

The document field is a full CNPJ for companies (`12.345.678/0001-00`) and a masked CPF for people (`•••.123.456-••`). A CNPJ is the most reliable key for categorizing merchants. Most rows in a typical month are Pix transfers.

## 2b. Nubank credit card CSV

Format (fake data):

```
date,title,amount
2026-09-29,Streaming Exemplo* Sub,"55,90"
2026-09-29,"IOF de ""Streaming Exemplo* Sub""","1,96"
2026-09-29,IOF de volta de Streaming Exemplo* Sub,"- 1,96"
2026-09-30,Hotel Exemplo - Parcela 1/6,"350,00"
2026-09-02,Pagamento recebido,"- 4.321,09"
```

- UTF-8, header `date,title,amount`. `date` is ISO (`YYYY-MM-DD`), unlike the account CSV.
- `amount` is quoted with a **comma decimal and dot thousands** (`"1.401,78"`), **positive = charge**, and negatives are written with a space (`"- 7,06"`). `Money.parse` drops the space, and the importer flips the sign so charges are negative on the card account like every other outflow.
- **No transaction ID.** The upsert key is derived like Itaú's: `sha256(card | bill due date | date | title | amount | k)`. `k` matters here: bills can contain truly identical rows (for example two memberships at the same gym charged the same amount on the same day), and `k` numbers them so they stay separate.
- **The bill's due date comes from the file name** (`Nubank_2026-09-09.csv`). A file without it is rejected with a message asking you to rename it, rather than guessing which bill it is.
- No summary line, so the check is against the account statement instead: **the sum of a bill's charges must equal the "Pagamento de fatura" that paid it** (once that account month is imported). A mismatch is a warning, not a rejection, because a bill can be paid partially, and IOF rounding inside the bank can leave a one-centavo gap. The importer never invents a balancing row.

Title patterns:

| Pattern | kind | Notes |
|---|---|---|
| `Pagamento recebido` | transfer ← Nubank conta | other leg of the account's "Pagamento de fatura" |
| `… - Parcela N/M` | purchase, installment N of M | `purchase_key` links the installments across bills. The export has no purchase date, so the key is merchant + installment count + installment amount |
| `Pix no Crédito - NAME - N/M` | purchase (a Pix paid with the card), installments | |
| `IOF de "X"` / `IOF de volta de X` | fee / refund of that fee | international purchases; Nubank refunds the IOF, so the pair nets to zero and both link to purchase X |
| `Estorno de "X"` | refund | linked to X when found |
| `Desconto Antecipação X` | refund | discount for paying installments early |
| `… - NuPay` | purchase | merchants paid via NuPay |
| anything else | purchase, or refund if negative | e.g. `Loja Exemplo - NuPay "- 17,99"` is a refund |

## 3. Itaú credit card PDF

The bill has a cover page with the summary and a boleto, then pages of transactions laid out in **two or three columns per page**. A plain text dump interleaves the columns, so the parser works from word positions:

1. Run `pdftotext -bbox <file> -` (poppler-utils), which outputs every word with its coordinates.
   Then **rejoin split words**: some bills draw text with tight letter spacing, so poppler splits words into fragments (`DAT A`, `LOJ A EXEM PLO`, `1.234 ,56`). Fragments less than 1,25 pt apart are glued back together; real spaces are 1,4 pt or more. Measured on real bills, the gaps split cleanly into two groups (0,2–1,2 pt inside words, 1,3–3 pt between words). But a bill *without* fragments puts its words only 1,2 pt apart, so the rejoin only runs on pages that look fragmented (more than 20% of the gaps under 1 pt).
2. On each page, find each `DATA … VALOR EM R$` column header. A column runs from its `DATA` to just past its `R$`, and the positions differ from page to page. Ending the column at `R$` matters: the last column often has another table beside it (limits, interest rates) whose lines would otherwise merge with the rows.
3. Within each column, group words into lines by y position. A line that starts with `DD/MM` and ends with an amount (`1.234,56` or `-64,66`) is a transaction. The line below it holds the bank's category and city (`vestuário Sao Paulo`).
4. Use section headings to decide what each row is: `Pagamentos efetuados` (payments), `Lançamentos: compras e saques` (purchases, possibly under a cardholder name such as `MARIA E SOUZA`), `Lançamentos: produtos e serviços` (fees and credits), and `Compras parceladas - próximas faturas` (future installments, not transactions of this bill).
5. Read the summary figures: total of this bill, previous bill, payments, `Lançamentos no cartão`, `Lançamentos produtos e serviços`, next bill, later bills, credit limit, closing date, due date.

A throwaway prototype of steps 1 to 4 matched the printed totals to the cent on four real bills:

```
purchases parsed            == "Lançamentos no cartão"
purchases + fees            == "Total desta fatura"
payment parsed (negated)    == previous bill's "Total desta fatura"
```

The last line is a second check that the bills chain without gaps.

The future-installments list matched "Próxima fatura" on most bills, but on one the prototype over-collected, because another table sits beside that list on the page (bounding columns at `R$`, step 2, fixed it). The importer still treats future installments as optional information: it stores the printed "Próxima fatura" and "Demais faturas", and logs a warning if the list doesn't add up to the first. It never rejects a bill over this.

**These equalities are the importer's safety check.** If the parsed rows don't add up to the printed totals to the cent, the import is rejected and nothing is written. That covers layout changes, a missed column, or a misread amount.

Details the parser handles:
- **Dates have no year.** The year comes from the closing date: a row dated after the closing month belongs to the previous year. For example, `23/11` on a bill closing 2026-10-02 is 2025-11-23.
- **Installments** appear as `LOJA EXEMPLO 11/12` (installment 11 of 12). The parser stores `installment_number` and `installment_total`, and strips the suffix from the description. It also builds `purchase_key` from merchant, purchase date, installment amount and total count, so the 12 rows of that purchase are linked across bills.
- **Negative rows**: `CANCELAMENTO DE COMPRA`, `CANCELAMENTO PARCIAL DE`, and merchant refunds such as `LOJA EXEMPLO -114,50` become refunds, as positive amounts on the card account.
- **Fees**: the card's monthly fee (`Mensalidade - Plano do`) and its discount (`Redução Mensalidade`, a negative row) both become `fee` rows (a "Tarifas bancárias" category comes in milestone 3). The line under them (`Anuidade Diferenciada`) is kept in the raw row.
- **Payments**: `Pagamento via conta -1.234,56` is the card side of a transfer from the Itaú checking account.
- **The bank's category** (`vestuário`, `supermercado`, `viagem`, `saúde`, `restaurante`, `lazer`, `educação`, `serviços`, `casa`, `eletronicos`, `outros`) is stored in `bank_category`, and the city in `location`. Itaú's categories are rough (online marketplace purchases are often "vestuário"), so they are only a fallback hint (§6).
- Merchant names are cut at about 23 characters and often have the city glued on (`PADARIA EXEMPLOSAO PAULO`). The raw text is kept, and a cleaned `description` drops known city suffixes.
- **Future installments** are not stored as transactions. They go into `card_statements.next_statement_cents` and `later_statements_cents`, so budgets can show money that is already committed.

Why poppler and not a gem: the pure-Ruby `pdf-reader` gem (2.16) returns positions but drops the spaces inside merchant names on these PDFs (`PADARIAEXEMPLO`), which hurts both display and rule matching. `poppler-utils` is a small Debian package, available on Raspberry Pi OS, and keeps the spaces. The parser calls `pdftotext` with `Open3.capture2` and an argument array, never through a shell string.

### Card merchants as counterparties

Card rows have no CNPJ, and the same merchant shows up under many names: a code that changes per purchase (`LOJA EXEMPLO*AB12`, `LOJA EXEMPLO*CD34`), a store number (`FARMACIA EXEMPLO 0123`), a payment processor's prefix (`PAG*Loja Exemplo`), and each bank cutting long names at its own length. A counterparty without a document is keyed by the merchant's stable part (`Tally::Merchants`): the text before `*` (or after it, for a known processor prefix), without trailing words that contain digits, ignoring case, spaces, punctuation and accents. A name that another bank cut shorter or longer joins the existing counterparty when the shorter key has at least 8 characters. The counterparty is named by that stable part; each row keeps its full description.

## 4. Re-importing a file (upsert)

If a file is imported again, the existing rows are updated instead of duplicated. Every import still gets its own row in `imports`, so there is a full history.

The import runs as one operation (`ImportStatement`), inside a single DB transaction:

1. Hash the file (SHA-256). If the same bytes were already imported, record an `imports` row with status `duplicate_file` and stop.
2. Parse into plain rows. A parser never touches the DB. Validate the rows (§3 totals for Itaú, and the format checks for both banks). On any failure, record status `rejected` with the reason, and write nothing else.
3. Compute each row's `external_id`:
   - **Nubank account**: the `Identificador` UUID plus the amount's sign (see §2).
   - **Itaú** has no IDs, so the key is derived: `sha256(card | due date | purchase date | raw description | installment n/m | amount | k)`. Here `k` numbers identical rows within the same bill. Repeat purchases (the same parking lot, same price, several times a month) show it can happen, and `k` keeps them as separate rows instead of merging them.
4. For each row, look up `(account_id, external_id)`:
   - **Not found**: insert it, and run categorization (§6).
   - **Found with the same values**: count it as unchanged, and update `last_import_id`.
   - **Found with different values**: update the bank-owned fields (amount, dates, descriptions, bank category, location, installments, counterparty, raw_json). **User-owned fields are never overwritten**: `category_id` when `category_source = 'manual'`, `memo`, and `cleared`.
5. Rows that belonged to the same account and period (Nubank) or the same bill (Itaú), but are missing from the new file, get `missing_since_import_id` set. They are not deleted, and they are listed on the import result page for you to confirm.
6. For Itaú, upsert the `card_statements` row on `(account_id, due_on)`.
7. Save the original file under `storage/imports/<sha256>.<ext>` so any import can be re-run or audited later.
8. Record the counts (`inserted`, `updated`, `unchanged`, `missing`) and show them.

**Transfers** (milestone 2, `PairTransfers`): a row marked as a transfer knows the other account (`counter_account_id`).
- When both accounts are imported (Nubank conta's "Pagamento de fatura" and the card's "Pagamento recebido"), the other leg is the row in that account with the opposite amount, pointing back, within 5 days. Both get the same `transfer_id`.
- The two account rows of a "Pix no Crédito" (same UUID, +X and −X) are paired with each other.
- When the other account has no statement (Itaú conta, Nubank RDB), a **mirror row** is written there (`external_id = mirror:<row id>`), so its balance is a plain `SUM`. A re-import that changes the amount updates the mirror.
- Otherwise (the other side not imported yet, or the dollar Conta Global) the row stays a one-leg transfer: still never spending or income.

**Cross-source checks** are on the Accounts page: each Nubank card bill against the account's "Pagamento de fatura" (between 20 days before and 5 days after the due date), and each Itaú bill against the payment printed on the next bill. A difference is a warning, never a rejection. The Itaú account's balance is flagged when it drifts more than `PASS_THROUGH_TOLERANCE_CENTS` (default R$ 50) from zero.

Overlapping files work too: a Nubank export for 15 Jun to 15 Jul followed by one for July only updates the shared rows and inserts the rest.

## 5. Which date counts for budgets

- **Account rows**: the transaction date.
- **Card purchases paid in one go**: the purchase date.
- **Card installments**: the bill's closing date, which is the month the installment is actually paid. The original purchase date is kept in `purchased_on`. Otherwise one 10-installment flight would land entirely in a month from 8 bills ago.

This is a default and easy to switch. It only changes which month a row counts toward in reports.

## 6. Categorization

The goal is to fill in as much as possible automatically, then make the remaining rows quick to fix by hand.

Each new row goes through these steps in order. The first one that matches sets the category and `category_source`:

1. **Transfers are never spending.** RDB moves, Itaú `Pagamento via conta`, and Pix to a counterparty marked `is_self` are marked as transfers and get no category. `Pagamento de fatura` (account) and `Pagamento recebido` (card) are the two legs of one transfer. You mark your own name and masked CPF with "This is me" on the Counterparties page, which sets `is_self` in your local database and turns your past Pix to yourself into transfers too. A Pix to yourself at Itaú becomes a transfer to "Itaú conta".
2. **Counterparty default**: if the counterparty has a `default_category_id`, use it.
3. **Rules** from `category_rules`, lowest `priority` first, matching on CNPJ, counterparty name, description, bank category, kind, and optional amount range.
4. **Bank hint**: map Itaú's `bank_category` to an app category (`supermercado` → Alimentação > Supermercado, `restaurante` → Alimentação > Restaurantes, `viagem` → Transporte > Viagens, `saúde` → Saúde, …). These rows are marked `category_source = 'bank'`, so they show as "suggested".
5. **Nothing matched**: the row stays uncategorized and goes to the review queue.

**Review queue**: uncategorized and bank-suggested rows, **grouped by counterparty**, with a total for each group. Picking a category for a group asks "always use this for <counterparty>?". A yes creates a `learned` rule (or sets the counterparty default) and re-applies it to every past row that isn't `manual`. Since most rows come from a few dozen counterparties, a handful of clicks covers a whole month.

**Seed rules** shipped in the repository are generic: well-known public merchants matched by name, so they work for any household. Examples:

| Match | Category |
|---|---|
| IFOOD, "NuPay - iFood" | Alimentação > Delivery |
| UBER, 99 TECNOLOGIA | Transporte > Aplicativo |
| POSTO …, SHELL, IPIRANGA | Transporte > Combustível |
| ESTACIONAMENTO…, PARKING | Transporte > Estacionamento |
| DROGASIL, DROGA RAIA, PAGUE MENOS | Saúde > Farmácia |
| PETZ, PETLOVE, COBASI | Pets |
| LATAM, GOL, AZUL | Transporte > Viagens |
| NETFLIX, SPOTIFY, AMAZON PRIME, DL*GOOGLE | Assinaturas |
| SECR. DA RECEITA FEDERAL (received) | Receitas > Restituição de IR |
| Itaú `Mensalidade` / `Anuidade` | Tarifas bancárias |

Rules for your own counterparties (your employer, your company, your utilities by CNPJ, your gym, people you pay) are created in your local database, through the review queue or a local seed file in `data/`, never in the repository.

**Pix sent to people** (CPF recipients) are auto-categorized as **Transferências (Pix)**, their own category. They count as spending, with nature essential, so the planner trims them by 15% at most. You can still move one recipient to a real category (for example rent or a cleaner) with a counterparty rule. Pix to your own accounts stays a transfer and is never spending.

Every row also keeps as much detail as the statement gives: counterparty with CPF/CNPJ and bank details, bank category, city, installment n/m with a link to the other installments, the bill it belongs to, the raw line, and the import it came from.

## 7. Tests

- **Golden files**: synthetic statements that copy each format and its quirks, with fake names and amounts (the repository is public, see architecture.md §17). Each has its expected parsed output, and the tests assert row counts, totals and keys. Real statements stay in the gitignored `data/` folder and are only used for an optional local check.
- **Cross-source tests**: each Nubank card bill matches the account's "Pagamento de fatura", and each Itaú payment equals the previous bill's total.
- **Re-import tests**: importing the same file twice changes nothing; a modified row updates; a removed row is flagged; a manual category survives a re-import.
- **Year-inference tests** around the December/January boundary.
