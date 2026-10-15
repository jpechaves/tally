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
  `warnings` text DEFAULT('[]') NOT NULL, `error` text,
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
INSERT INTO schema_migrations (filename) VALUES
('20261015000000_create_accounts.rb'),
('20261015100000_create_import_tables.rb');
