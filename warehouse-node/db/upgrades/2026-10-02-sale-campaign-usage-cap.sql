-- =====================================================================================
-- Upgrade an EXISTING warehouse_db to the current schema: per-customer usage cap on a sale
-- campaign. Run AFTER 2026-10-02-sale-campaign-edit-reopen.sql. A fresh install does NOT need
-- this (db/schema.sql already has it).
--
-- Run ONCE, after a backup:
--   mysqldump -u root warehouse_db sale_campaigns > sale_campaigns-usage-cap-backup.sql
--   mysql -u root warehouse_db < db/upgrades/2026-10-02-sale-campaign-usage-cap.sql
--
-- New nullable column only — no existing row needs a value (NULL = unlimited, today's behaviour).
-- =====================================================================================
SET NAMES utf8mb4;

ALTER TABLE `sale_campaigns`
  ADD COLUMN `max_uses_per_customer` int DEFAULT NULL AFTER `first_activated_at`,
  ADD CONSTRAINT `sale_campaigns_max_uses_positive` CHECK (`max_uses_per_customer` > 0);
