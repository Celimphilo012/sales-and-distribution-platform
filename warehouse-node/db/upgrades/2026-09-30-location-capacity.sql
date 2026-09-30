-- =====================================================================================
-- Upgrade an EXISTING warehouse_db to the current schema: location capacity.
-- Run AFTER 2026-09-28-security-notifications-packing.sql. A fresh install does NOT need this.
--
-- Run ONCE, after a backup:
--   mysqldump -u root warehouse_db > warehouse_db-backup.sql
--   mysql -u root warehouse_db < db/upgrades/2026-09-30-location-capacity.sql
--
-- `capacity` is how many units a location holds when full (usually set on storage slots). It feeds
-- the Warehouse Console's fill / utilisation bars. NULL = not set (no bar shown). Report branding
-- (company name + logo) needs no schema change — it lives in app_settings.
-- =====================================================================================
SET NAMES utf8mb4;

ALTER TABLE `locations` ADD COLUMN `capacity` int(11) DEFAULT NULL AFTER `description`;
