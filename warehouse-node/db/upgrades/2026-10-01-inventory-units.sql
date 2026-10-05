-- =====================================================================================
-- Upgrade an EXISTING warehouse_db to the current schema: per-unit (serial) tracking.
-- Run AFTER 2026-09-30-location-capacity.sql. A fresh install does NOT need this.
--
-- Run ONCE, after a backup:
--   mysqldump -u root warehouse_db > warehouse_db-backup.sql
--   mysql -u root warehouse_db < db/upgrades/2026-10-01-inventory-units.sql
--
-- Opt-in per product (`tracking_mode`, default BULK — every existing product is unaffected).
-- A SERIAL product gets one `inventory_units` row per physical unit, written only by
-- InventoryService.applyTransaction() alongside the usual inventory_balances delta, so the two
-- never drift. `inventory_transaction_units` records which specific units moved in each ledger
-- entry (a unit's full history = its rows here, joined to inventory_transactions).
-- =====================================================================================
SET NAMES utf8mb4;

ALTER TABLE `products` ADD COLUMN `tracking_mode` enum('BULK','SERIAL') NOT NULL DEFAULT 'BULK' AFTER `status`;

CREATE TABLE `inventory_units` (
  `id` varchar(191) NOT NULL,
  `product_id` varchar(191) NOT NULL,
  `unit_code` varchar(191) NOT NULL,
  `source` enum('GENERATED','SUPPLIER') NOT NULL,
  `status` enum('PENDING','ON_HAND','RESERVED','DAMAGED','LOST','EXPIRED','ISSUED') NOT NULL DEFAULT 'PENDING',
  `location_id` varchar(191) DEFAULT NULL,
  `created_at` datetime(3) NOT NULL DEFAULT current_timestamp(3),
  `updated_at` datetime(3) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `inventory_units_unit_code_key` (`unit_code`),
  KEY `inventory_units_product_id_idx` (`product_id`),
  KEY `inventory_units_location_id_idx` (`location_id`),
  CONSTRAINT `inventory_units_location_id_fkey` FOREIGN KEY (`location_id`) REFERENCES `locations` (`id`) ON UPDATE CASCADE,
  CONSTRAINT `inventory_units_product_id_fkey` FOREIGN KEY (`product_id`) REFERENCES `products` (`id`) ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `inventory_transaction_units` (
  `transaction_id` varchar(191) NOT NULL,
  `unit_id` varchar(191) NOT NULL,
  PRIMARY KEY (`transaction_id`,`unit_id`),
  KEY `inventory_transaction_units_unit_id_idx` (`unit_id`),
  CONSTRAINT `inventory_transaction_units_transaction_id_fkey` FOREIGN KEY (`transaction_id`) REFERENCES `inventory_transactions` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `inventory_transaction_units_unit_id_fkey` FOREIGN KEY (`unit_id`) REFERENCES `inventory_units` (`id`) ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
