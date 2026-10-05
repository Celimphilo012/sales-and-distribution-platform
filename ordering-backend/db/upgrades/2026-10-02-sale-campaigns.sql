-- =====================================================================================
-- Upgrade an EXISTING distribution_platform to the current schema: sale campaign pricing.
-- A fresh install does NOT need this.
--
-- Run ONCE, after a backup:
--   mysqldump -u root distribution_platform > distribution_platform-backup.sql
--   mysql -u root distribution_platform < db/upgrades/2026-10-02-sale-campaigns.sql
--
-- Pairs with warehouse_db's own db/upgrades/2026-10-02-sale-campaigns.sql (sale campaigns
-- themselves live there — this side only snapshots a discount onto an order line, and keeps the
-- LOCAL eligibility list for a RESTRICTED campaign, since customers are ours).
-- =====================================================================================
SET NAMES utf8mb4;

ALTER TABLE `order_items`
  ADD COLUMN `original_unit_price` decimal(12,2) DEFAULT NULL AFTER `unit_price`,
  ADD COLUMN `sale_campaign_id` varchar(191) DEFAULT NULL,
  ADD COLUMN `sale_campaign_name` varchar(191) DEFAULT NULL;

CREATE TABLE `sale_campaign_eligible_customers` (
  `id` varchar(191) NOT NULL,
  `sale_campaign_id` varchar(191) NOT NULL,
  `customer_id` varchar(191) NOT NULL,
  `created_at` datetime(3) NOT NULL DEFAULT current_timestamp(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `sale_campaign_eligible_customers_campaign_customer_key` (`sale_campaign_id`,`customer_id`),
  KEY `sale_campaign_eligible_customers_customer_id_idx` (`customer_id`),
  CONSTRAINT `sale_campaign_eligible_customers_customer_id_fkey` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
