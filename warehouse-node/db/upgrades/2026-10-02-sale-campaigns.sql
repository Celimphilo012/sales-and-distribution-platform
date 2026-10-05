-- =====================================================================================
-- Upgrade an EXISTING warehouse_db to the current schema: sale campaigns (discounts).
-- Run AFTER 2026-10-01-inventory-units.sql. A fresh install does NOT need this.
--
-- Run ONCE, after a backup:
--   mysqldump -u root warehouse_db > warehouse_db-backup.sql
--   mysql -u root warehouse_db < db/upgrades/2026-10-02-sale-campaigns.sql
--
-- New tables only — no existing table changes, nothing to affect existing data. After this runs,
-- add a cPanel Cron Job (see README.md) so SCHEDULED/ACTIVE transitions actually happen:
--   * * * * *  node /home/<user>/<app-root>/scripts/sales-tick.js >> sales-tick.log 2>&1
-- =====================================================================================
SET NAMES utf8mb4;

CREATE TABLE `sale_campaigns` (
  `id` varchar(191) NOT NULL,
  `name` varchar(191) NOT NULL,
  `description` varchar(500) DEFAULT NULL,
  `starts_at` datetime(3) NOT NULL,
  `ends_at` datetime(3) NOT NULL,
  `eligibility` enum('ALL_CUSTOMERS','RESTRICTED') NOT NULL DEFAULT 'ALL_CUSTOMERS',
  `status` enum('PENDING_APPROVAL','SCHEDULED','ACTIVE','ENDED','REJECTED','CANCELLED') NOT NULL DEFAULT 'PENDING_APPROVAL',
  `requested_by` varchar(191) NOT NULL,
  `requested_at` datetime(3) NOT NULL DEFAULT current_timestamp(3),
  `reviewed_by` varchar(191) DEFAULT NULL,
  `reviewed_at` datetime(3) DEFAULT NULL,
  `review_note` varchar(191) DEFAULT NULL,
  `created_at` datetime(3) NOT NULL DEFAULT current_timestamp(3),
  `updated_at` datetime(3) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `sale_campaigns_status_idx` (`status`),
  KEY `sale_campaigns_requested_by_fkey` (`requested_by`),
  KEY `sale_campaigns_reviewed_by_fkey` (`reviewed_by`),
  CONSTRAINT `sale_campaigns_requested_by_fkey` FOREIGN KEY (`requested_by`) REFERENCES `users` (`id`) ON UPDATE CASCADE,
  CONSTRAINT `sale_campaigns_reviewed_by_fkey` FOREIGN KEY (`reviewed_by`) REFERENCES `users` (`id`) ON UPDATE CASCADE,
  CONSTRAINT `sale_campaigns_ends_after_starts` CHECK (`ends_at` > `starts_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `sale_campaign_products` (
  `id` varchar(191) NOT NULL,
  `campaign_id` varchar(191) NOT NULL,
  `product_id` varchar(191) NOT NULL,
  `discount_type` enum('PERCENT','FIXED_AMOUNT','FIXED_PRICE') NOT NULL,
  `discount_value` decimal(12,2) NOT NULL,
  `min_quantity` decimal(12,3) NOT NULL DEFAULT 1.000,
  PRIMARY KEY (`id`),
  UNIQUE KEY `sale_campaign_products_campaign_id_product_id_key` (`campaign_id`,`product_id`),
  KEY `sale_campaign_products_product_id_idx` (`product_id`),
  CONSTRAINT `sale_campaign_products_campaign_id_fkey` FOREIGN KEY (`campaign_id`) REFERENCES `sale_campaigns` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `sale_campaign_products_product_id_fkey` FOREIGN KEY (`product_id`) REFERENCES `products` (`id`) ON UPDATE CASCADE,
  CONSTRAINT `sale_campaign_products_discount_value_positive` CHECK (`discount_value` > 0),
  CONSTRAINT `sale_campaign_products_min_quantity_positive` CHECK (`min_quantity` > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
