-- =====================================================================================
-- Upgrade an EXISTING warehouse_db (created before 2026-09-28) to the current schema.
-- A fresh install does NOT need this — load db/schema.sql instead.
--
-- Run ONCE, after a backup:
--   mysqldump -u root warehouse_db > warehouse_db-backup.sql
--   mysql -u root warehouse_db < db/upgrades/2026-09-28-security-notifications-packing.sql
--
-- Adds: user phone / notification channel / MFA columns, warehouse access assignments,
-- one-time-code challenges, the notifications log, admin-editable delivery settings,
-- the reservation label (packing), and their permissions (granted to ADMIN etc.).
-- Also remove the Prisma leftover if it is still there:  DROP TABLE IF EXISTS _prisma_migrations;
-- =====================================================================================

-- One-off schema change: contact fields + MFA on users, warehouse access assignments,
-- one-time-code challenges, and a log of sent notifications. Run once per existing database.
SET NAMES utf8mb4;

ALTER TABLE `users`
  ADD COLUMN `phone` varchar(32) DEFAULT NULL AFTER `full_name`,
  ADD COLUMN `notify_channel` enum('EMAIL','SMS','NONE') NOT NULL DEFAULT 'EMAIL' AFTER `phone`,
  ADD COLUMN `mfa_method` enum('NONE','EMAIL','SMS','TOTP') NOT NULL DEFAULT 'NONE' AFTER `notify_channel`,
  ADD COLUMN `totp_secret` varchar(255) DEFAULT NULL AFTER `mfa_method`;

CREATE TABLE `user_warehouses` (
  `id` varchar(191) NOT NULL,
  `user_id` varchar(191) NOT NULL,
  `warehouse_id` varchar(191) NOT NULL,
  `created_at` datetime(3) NOT NULL DEFAULT current_timestamp(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `user_warehouses_user_id_warehouse_id_key` (`user_id`,`warehouse_id`),
  KEY `user_warehouses_warehouse_id_idx` (`warehouse_id`),
  CONSTRAINT `user_warehouses_user_id_fkey` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `user_warehouses_warehouse_id_fkey` FOREIGN KEY (`warehouse_id`) REFERENCES `warehouses` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `otp_challenges` (
  `id` varchar(191) NOT NULL,
  `user_id` varchar(191) NOT NULL,
  `purpose` enum('LOGIN','ACTION','MFA_SETUP') NOT NULL,
  `channel` enum('EMAIL','SMS','TOTP') NOT NULL,
  `action` varchar(191) DEFAULT NULL,
  `target_id` varchar(191) DEFAULT NULL,
  `code_hash` varchar(191) DEFAULT NULL,
  `pending_secret` varchar(255) DEFAULT NULL,
  `attempts` int(11) NOT NULL DEFAULT 0,
  `expires_at` datetime(3) NOT NULL,
  `consumed_at` datetime(3) DEFAULT NULL,
  `created_at` datetime(3) NOT NULL DEFAULT current_timestamp(3),
  PRIMARY KEY (`id`),
  KEY `otp_challenges_user_id_created_at_idx` (`user_id`,`created_at`),
  CONSTRAINT `otp_challenges_user_id_fkey` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `notifications` (
  `id` varchar(191) NOT NULL,
  `user_id` varchar(191) DEFAULT NULL,
  `event` varchar(191) NOT NULL,
  `channel` enum('EMAIL','SMS') NOT NULL,
  `destination` varchar(191) NOT NULL,
  `subject` varchar(191) DEFAULT NULL,
  `body` text NOT NULL,
  `status` enum('SENT','LOGGED','FAILED') NOT NULL,
  `error` text DEFAULT NULL,
  `created_at` datetime(3) NOT NULL DEFAULT current_timestamp(3),
  PRIMARY KEY (`id`),
  KEY `notifications_user_id_idx` (`user_id`),
  KEY `notifications_created_at_idx` (`created_at`),
  CONSTRAINT `notifications_user_id_fkey` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- New permissions, granted to ADMIN (the seed's catalog lists them too).
INSERT IGNORE INTO `permissions` (`id`, `key`, `description`, `module`) VALUES
  (UUID(), 'warehouse.access.all', 'Access every warehouse without being assigned to it', 'warehouses'),
  (UUID(), 'warehouse.access.assign', 'Assign users to the warehouses they may access', 'warehouses');
INSERT IGNORE INTO `role_permissions` (`role_id`, `permission_id`)
  SELECT r.id, p.id FROM `roles` r JOIN `permissions` p ON p.`key` IN ('warehouse.access.all', 'warehouse.access.assign')
   WHERE r.name = 'ADMIN';

-- Access is deny-by-default from now on. So nobody loses access on upgrade, every existing user
-- (except the internal API user) is assigned to every existing warehouse; narrow it from the UI.
INSERT IGNORE INTO `user_warehouses` (`id`, `user_id`, `warehouse_id`, `created_at`)
  SELECT UUID(), u.id, w.id, UTC_TIMESTAMP(3) FROM `users` u CROSS JOIN `warehouses` w
   WHERE u.email <> 'system.api@warehouse.internal';

-- One-off schema change: admin-editable settings (email/SMS delivery) and settings.manage.
SET NAMES utf8mb4;

CREATE TABLE `app_settings` (
  `key` varchar(100) NOT NULL,
  `value` text DEFAULT NULL,
  `is_secret` tinyint(1) NOT NULL DEFAULT 0,
  `updated_by` varchar(191) DEFAULT NULL,
  `updated_at` datetime(3) NOT NULL DEFAULT current_timestamp(3),
  PRIMARY KEY (`key`),
  KEY `app_settings_updated_by_fkey` (`updated_by`),
  CONSTRAINT `app_settings_updated_by_fkey` FOREIGN KEY (`updated_by`) REFERENCES `users` (`id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO `permissions` (`id`, `key`, `description`, `module`) VALUES
  (UUID(), 'settings.manage', 'Configure system settings such as email (SMTP) and SMS (httpSMS) delivery', 'settings');
INSERT IGNORE INTO `role_permissions` (`role_id`, `permission_id`)
  SELECT r.id, p.id FROM `roles` r JOIN `permissions` p ON p.`key` = 'settings.manage' WHERE r.name = 'ADMIN';

-- One-off schema change: a human label on stock reservations (e.g. "ORD-0012 · Customer") and the
-- packing.view permission. Run once per existing database.
SET NAMES utf8mb4;

ALTER TABLE `stock_reservations` ADD COLUMN `label` varchar(191) DEFAULT NULL AFTER `reference`;

INSERT IGNORE INTO `permissions` (`id`, `key`, `description`, `module`) VALUES
  (UUID(), 'packing.view', 'See the items to pack for open orders (within their warehouses and workstreams)', 'inventory');
INSERT IGNORE INTO `role_permissions` (`role_id`, `permission_id`)
  SELECT r.id, p.id FROM `roles` r JOIN `permissions` p ON p.`key` = 'packing.view'
   WHERE r.name IN ('ADMIN', 'WAREHOUSE', 'MANAGER', 'WORKSTREAM_MANAGER');
