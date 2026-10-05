-- =====================================================================================
-- Upgrade an EXISTING distribution_platform to the current schema: the Finances screen
-- (expense tracking + margin reporting). A fresh install does NOT need this.
--
-- Run ONCE, after a backup:
--   mysqldump -u root distribution_platform > distribution_platform-backup.sql
--   mysql -u root distribution_platform < db/upgrades/2026-10-02-finances.sql
--   npm run seed   (re-syncs the new finances.* permission keys)
-- =====================================================================================
SET NAMES utf8mb4;

CREATE TABLE `expenses` (
  `id` varchar(191) NOT NULL,
  `category` enum('RENT','SALARIES','UTILITIES','TRANSPORT','MARKETING','SUPPLIES','OTHER') NOT NULL,
  `amount` decimal(12,2) NOT NULL,
  `description` varchar(500) DEFAULT NULL,
  `incurred_at` date NOT NULL,
  `status` enum('RECORDED','VOIDED') NOT NULL DEFAULT 'RECORDED',
  `recorded_by` varchar(191) NOT NULL,
  `voided_by` varchar(191) DEFAULT NULL,
  `voided_at` datetime(3) DEFAULT NULL,
  `void_reason` varchar(500) DEFAULT NULL,
  `created_at` datetime(3) NOT NULL DEFAULT current_timestamp(3),
  `updated_at` datetime(3) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `expenses_incurred_at_idx` (`incurred_at`),
  KEY `expenses_recorded_by_fkey` (`recorded_by`),
  KEY `expenses_voided_by_fkey` (`voided_by`),
  CONSTRAINT `expenses_recorded_by_fkey` FOREIGN KEY (`recorded_by`) REFERENCES `users` (`id`) ON UPDATE CASCADE,
  CONSTRAINT `expenses_voided_by_fkey` FOREIGN KEY (`voided_by`) REFERENCES `users` (`id`) ON UPDATE CASCADE,
  CONSTRAINT `expenses_amount_positive` CHECK (`amount` > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE `order_items`
  ADD COLUMN `unit_cost` decimal(12,2) DEFAULT NULL AFTER `sale_campaign_name`;
