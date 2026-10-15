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
  CONSTRAINT `accounts_kind` CHECK(kind IN('checking', 'credit_card', 'investment', 'cash')),
  CONSTRAINT `accounts_currency` CHECK(currency GLOB '[A-Z][A-Z][A-Z]')
) STRICT;
INSERT INTO schema_migrations (filename) VALUES
('20261015000000_create_accounts.rb');
