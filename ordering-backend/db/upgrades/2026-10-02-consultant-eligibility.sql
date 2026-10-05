-- =====================================================================================
-- Upgrade an EXISTING distribution_platform to the current schema: sale-campaign eligibility is
-- now assigned by CONSULTANT, not by individual customer — every customer assigned to an eligible
-- consultant qualifies for a RESTRICTED campaign's price. A fresh install does NOT need this.
--
-- `sale_campaign_eligible_customers` is only days old and not in real use yet, so this is a clean
-- drop + recreate under the new name/shape rather than a data-migrating rename — if it already
-- holds real eligibility rows you want to keep, re-enter them afterward via the new
-- "eligible consultants" screen instead of relying on this script to carry them over.
--
-- Run ONCE, after a backup:
--   mysqldump -u root distribution_platform customers sale_campaign_eligible_customers > consultant-eligibility-backup.sql
--   mysql -u root distribution_platform < db/upgrades/2026-10-02-consultant-eligibility.sql
-- =====================================================================================
SET NAMES utf8mb4;

ALTER TABLE `customers`
  ADD COLUMN `assigned_consultant_id` varchar(191) DEFAULT NULL AFTER `notes`,
  ADD KEY `customers_assigned_consultant_id_idx` (`assigned_consultant_id`),
  ADD CONSTRAINT `customers_assigned_consultant_id_fkey` FOREIGN KEY (`assigned_consultant_id`) REFERENCES `users` (`id`) ON UPDATE CASCADE;

DROP TABLE IF EXISTS `sale_campaign_eligible_customers`;

CREATE TABLE `sale_campaign_eligible_consultants` (
  `id` varchar(191) NOT NULL,
  `sale_campaign_id` varchar(191) NOT NULL,
  `consultant_id` varchar(191) NOT NULL,
  `created_at` datetime(3) NOT NULL DEFAULT current_timestamp(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `sale_campaign_eligible_consultants_campaign_consultant_key` (`sale_campaign_id`,`consultant_id`),
  KEY `sale_campaign_eligible_consultants_consultant_id_idx` (`consultant_id`),
  CONSTRAINT `sale_campaign_eligible_consultants_consultant_id_fkey` FOREIGN KEY (`consultant_id`) REFERENCES `users` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
