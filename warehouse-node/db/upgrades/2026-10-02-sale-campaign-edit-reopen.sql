-- =====================================================================================
-- Upgrade an EXISTING warehouse_db to the current schema: sale campaign edit/reopen +
-- daily time-of-day window. Run AFTER 2026-10-02-sale-campaigns.sql. A fresh install does NOT
-- need this (db/schema.sql already has it).
--
-- Run ONCE, after a backup:
--   mysqldump -u root warehouse_db sale_campaigns sale_campaign_products > sale_campaigns-backup.sql
--   mysql -u root warehouse_db < db/upgrades/2026-10-02-sale-campaign-edit-reopen.sql
--
-- New nullable columns only — no existing row needs a value, nothing to backfill.
-- =====================================================================================
SET NAMES utf8mb4;

ALTER TABLE `sale_campaigns`
  ADD COLUMN `daily_window_start` time DEFAULT NULL AFTER `review_note`,
  ADD COLUMN `daily_window_end` time DEFAULT NULL AFTER `daily_window_start`,
  ADD COLUMN `first_activated_at` datetime(3) DEFAULT NULL AFTER `daily_window_end`,
  ADD CONSTRAINT `sale_campaigns_daily_window_both_or_neither`
    CHECK ((`daily_window_start` IS NULL) = (`daily_window_end` IS NULL)),
  ADD CONSTRAINT `sale_campaigns_daily_window_order` CHECK (`daily_window_end` > `daily_window_start`);
