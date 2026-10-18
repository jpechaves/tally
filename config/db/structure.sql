CREATE TABLE `schema_migrations`(`filename` varchar(255) NOT NULL PRIMARY KEY);
CREATE TABLE `accounts`(
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT,
  `name` text NOT NULL UNIQUE,
  `kind` text NOT NULL,
  `institution` text,
  `external_ref` text,
  `currency` text DEFAULT('BRL') NOT NULL,
  `opening_balance_cents` integer DEFAULT(0) NOT NULL,
  `archived_at` text,
  `created_at` text DEFAULT((strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))) NOT NULL,
  `updated_at` text DEFAULT((strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))) NOT NULL,
  `mirror_transfers` integer DEFAULT(0) NOT NULL,
  CONSTRAINT `accounts_kind` CHECK(kind IN('checking', 'credit_card', 'investment', 'cash')),
  CONSTRAINT `accounts_currency` CHECK(currency GLOB '[A-Z][A-Z][A-Z]')
) STRICT;
CREATE TABLE `counterparties`(
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT,
  `name` text NOT NULL,
  `document` text,
  `document_kind` text,
  `match_key` text NOT NULL UNIQUE,
  `bank_name` text,
  `bank_code` text,
  `branch` text,
  `account_number` text,
  `is_self` integer DEFAULT(0) NOT NULL,
  `created_at` text DEFAULT((strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))) NOT NULL,
  `updated_at` text DEFAULT((strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))) NOT NULL,
  `default_category_id` integer REFERENCES `categories`,
  display_name text,
  note text,
  CONSTRAINT `counterparties_document_kind` CHECK(document_kind IN('cnpj', 'cpf_masked')),
  CONSTRAINT `counterparties_is_self` CHECK(is_self IN(0, 1))
) STRICT;
CREATE TABLE `imports`(
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT,
  `account_id` integer REFERENCES `accounts`,
  `source` text NOT NULL,
  `file_name` text NOT NULL,
  `file_sha256` text NOT NULL,
  `file_size` integer NOT NULL,
  `period_start` text,
  `period_end` text,
  `status` text NOT NULL,
  `rows_inserted` integer DEFAULT(0) NOT NULL,
  `rows_updated` integer DEFAULT(0) NOT NULL,
  `rows_unchanged` integer DEFAULT(0) NOT NULL,
  `rows_missing` integer DEFAULT(0) NOT NULL,
  `warnings` text DEFAULT('[]') NOT NULL,
  `error` text,
  `created_at` text DEFAULT((strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))) NOT NULL,
  `updated_at` text DEFAULT((strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))) NOT NULL,
  CONSTRAINT `imports_status` CHECK(status IN('applied', 'duplicate_file', 'rejected'))
) STRICT;
CREATE INDEX `imports_file_sha256_index` ON `imports`(`file_sha256`);
CREATE TABLE `card_statements`(
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT,
  `account_id` integer NOT NULL REFERENCES `accounts`,
  `closing_on` text,
  `due_on` text NOT NULL,
  `total_cents` integer NOT NULL,
  `previous_total_cents` integer,
  `payments_cents` integer DEFAULT(0) NOT NULL,
  `purchases_cents` integer DEFAULT(0) NOT NULL,
  `fees_cents` integer DEFAULT(0) NOT NULL,
  `next_statement_cents` integer,
  `later_statements_cents` integer,
  `credit_limit_cents` integer,
  `available_limit_cents` integer,
  `import_id` integer NOT NULL REFERENCES `imports`,
  `created_at` text DEFAULT((strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))) NOT NULL,
  `updated_at` text DEFAULT((strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))) NOT NULL,
  UNIQUE(`account_id`, `due_on`)
) STRICT;
CREATE TABLE `transfers`(
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT,
  `occurred_on` text NOT NULL,
  `memo` text,
  `created_at` text DEFAULT((strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))) NOT NULL,
  `updated_at` text DEFAULT((strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))) NOT NULL
) STRICT;
CREATE TABLE `transactions`(
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT,
  `account_id` integer NOT NULL REFERENCES `accounts`,
  `occurred_on` text NOT NULL,
  `purchased_on` text,
  `amount_cents` integer NOT NULL,
  `kind` text NOT NULL,
  `transfer_id` integer REFERENCES `transfers`,
  `counter_account_id` integer REFERENCES `accounts`,
  `counterparty_id` integer REFERENCES `counterparties`,
  `description` text NOT NULL,
  `raw_description` text NOT NULL,
  `bank_category` text,
  `location` text,
  `installment_number` integer,
  `installment_total` integer,
  `purchase_key` text,
  `card_statement_id` integer REFERENCES `card_statements`,
  `memo` text,
  `external_id` text NOT NULL,
  `first_import_id` integer REFERENCES `imports`,
  `last_import_id` integer REFERENCES `imports`,
  `missing_since_import_id` integer REFERENCES `imports`,
  `raw_json` text,
  `created_at` text DEFAULT((strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))) NOT NULL,
  `updated_at` text DEFAULT((strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))) NOT NULL,
  `category_id` integer REFERENCES `categories`,
  `category_source` text DEFAULT('none') NOT NULL,
  `category_rule_id` integer REFERENCES `category_rules`,
  exchange_currency text CHECK(exchange_currency IS NULL OR exchange_currency GLOB '[A-Z][A-Z][A-Z]'),
  exchange_amount_cents integer,
  exchange_rate text,
  fee_cents integer CHECK(fee_cents IS NULL OR fee_cents > 0),
  CONSTRAINT `transactions_amount` CHECK(amount_cents <> 0),
  CONSTRAINT `transactions_kind` CHECK(kind IN('purchase', 'refund', 'fee', 'income', 'transfer', 'bill_payment')),
  CONSTRAINT `transactions_installment` CHECK((installment_number IS NULL) =(installment_total IS NULL)),
  UNIQUE(`account_id`, `external_id`)
) STRICT;
CREATE INDEX `transactions_account_id_occurred_on_index` ON `transactions`(
  `account_id`,
  `occurred_on`
);
CREATE INDEX `transactions_counterparty_id_index` ON `transactions`(
  `counterparty_id`
);
CREATE INDEX `transactions_transfer_id_index` ON `transactions`(`transfer_id`);
CREATE INDEX `transactions_card_statement_id_index` ON `transactions`(
  `card_statement_id`
);
CREATE TABLE `categories`(
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT,
  `name` text NOT NULL,
  `parent_id` integer REFERENCES `categories`,
  `kind` text NOT NULL,
  `nature` text,
  `max_cut_pct` integer,
  `archived_at` text,
  `created_at` text DEFAULT((strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))) NOT NULL,
  `updated_at` text DEFAULT((strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))) NOT NULL,
  CONSTRAINT `categories_kind` CHECK(kind IN('expense', 'income')),
  CONSTRAINT `categories_nature` CHECK(nature IN('fixed', 'essential', 'discretionary')),
  CONSTRAINT `categories_max_cut_pct` CHECK(max_cut_pct BETWEEN 0 AND 100)
) STRICT;
CREATE UNIQUE INDEX `categories_parent_name` ON `categories`(
  `parent_id`,
  `name`
) WHERE(`parent_id` IS NOT NULL);
CREATE UNIQUE INDEX `categories_top_name` ON `categories`(
  `name`
) WHERE(`parent_id` IS NULL);
CREATE TABLE `category_rules`(
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT,
  `priority` integer DEFAULT(100) NOT NULL,
  `field` text NOT NULL,
  `operator` text NOT NULL,
  `pattern` text NOT NULL,
  `amount_min_cents` integer,
  `amount_max_cents` integer,
  `category_id` integer NOT NULL REFERENCES `categories`,
  `origin` text NOT NULL,
  `hits` integer DEFAULT(0) NOT NULL,
  `disabled_at` text,
  `created_at` text DEFAULT((strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))) NOT NULL,
  `updated_at` text DEFAULT((strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))) NOT NULL,
  CONSTRAINT `category_rules_field` CHECK(field IN('counterparty_document', 'counterparty_name', 'description', 'bank_category', 'kind')),
  CONSTRAINT `category_rules_operator` CHECK(operator IN('equals', 'contains', 'starts_with', 'regex')),
  CONSTRAINT `category_rules_origin` CHECK(origin IN('seed', 'learned', 'manual'))
) STRICT;
CREATE INDEX `category_rules_priority_id_index` ON `category_rules`(
  `priority`,
  `id`
);
CREATE INDEX `transactions_category_id_occurred_on_index` ON `transactions`(
  `category_id`,
  `occurred_on`
);
CREATE TABLE `dismissed_suggestions`(
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT,
  `key` text NOT NULL UNIQUE,
  `title` text NOT NULL,
  `created_at` text DEFAULT((strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))) NOT NULL
) STRICT;
CREATE TABLE `savings_plans`(
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT,
  `target_cents` integer NOT NULL,
  `baseline_from` text NOT NULL,
  `baseline_to` text NOT NULL,
  `baseline_income_cents` integer NOT NULL,
  `baseline_spending_cents` integer NOT NULL,
  `starts_month` text NOT NULL,
  `status` text DEFAULT('draft') NOT NULL,
  `shortfall_cents` integer DEFAULT(0) NOT NULL,
  `created_at` text DEFAULT((strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))) NOT NULL,
  `updated_at` text DEFAULT((strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))) NOT NULL,
  CONSTRAINT `savings_plans_target` CHECK(target_cents > 0),
  CONSTRAINT `savings_plans_status` CHECK(status IN('draft', 'active', 'replaced'))
) STRICT;
CREATE TABLE `savings_plan_lines`(
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT,
  `savings_plan_id` integer NOT NULL REFERENCES `savings_plans` ON DELETE CASCADE,
  `category_id` integer NOT NULL REFERENCES `categories`,
  `baseline_cents` integer NOT NULL,
  `max_cut_cents` integer NOT NULL,
  `proposed_cents` integer NOT NULL,
  CONSTRAINT `savings_plan_lines_proposed` CHECK(proposed_cents >= 0)
) STRICT;
CREATE UNIQUE INDEX `savings_plan_lines_savings_plan_id_category_id_index` ON `savings_plan_lines`(
  `savings_plan_id`,
  `category_id`
);
CREATE TABLE `budgets`(
  `id` integer NOT NULL PRIMARY KEY AUTOINCREMENT,
  `category_id` integer NOT NULL REFERENCES `categories`,
  `month` text NOT NULL,
  `amount_cents` integer NOT NULL,
  `savings_plan_id` integer REFERENCES `savings_plans`,
  `created_at` text DEFAULT((strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))) NOT NULL,
  `updated_at` text DEFAULT((strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))) NOT NULL,
  removed integer NOT NULL DEFAULT 0 CHECK(removed IN(0, 1)),
  CONSTRAINT `budgets_amount` CHECK(amount_cents >= 0)
) STRICT;
CREATE UNIQUE INDEX `budgets_category_id_month_index` ON `budgets`(
  `category_id`,
  `month`
);
INSERT INTO schema_migrations (filename) VALUES
('20261015000000_create_accounts.rb'),
('20261015100000_create_import_tables.rb'),
('20261016000000_create_categories.rb'),
('20261017000000_create_dismissed_suggestions.rb'),
('20261018000000_create_savings_plans_and_budgets.rb'),
('20261019000000_add_removed_to_budgets.rb'),
('20261020000000_add_exchange_to_transactions.rb'),
('20261021000000_add_display_name_and_note_to_counterparties.rb');
