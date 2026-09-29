-- =====================================================================================
-- Upgrade an EXISTING distribution_platform (created before 2026-09-29) to the current schema.
-- A fresh install does NOT need this — load db/schema.sql instead.
--
-- Run ONCE, after a backup:
--   mysqldump -u root distribution_platform > distribution_platform-backup.sql
--   mysql -u root distribution_platform < db/upgrades/2026-09-29-payments-security-notifications.sql
--
-- Adds: payments against orders, user phone / notification channel / MFA columns, one-time-code
-- challenges, the notifications log, admin-editable delivery settings (app_settings), and the new
-- permissions payments.record / payments.void (ADMIN + MANAGER) and settings.manage (ADMIN).
-- =====================================================================================
SET NAMES utf8mb4;

ALTER TABLE `users`
  ADD COLUMN `phone` varchar(32) DEFAULT NULL AFTER `full_name`,
  ADD COLUMN `notify_channel` enum('EMAIL','SMS','NONE') NOT NULL DEFAULT 'EMAIL' AFTER `phone`,
  ADD COLUMN `mfa_method` enum('NONE','EMAIL','SMS','TOTP') NOT NULL DEFAULT 'NONE' AFTER `notify_channel`,
  ADD COLUMN `totp_secret` varchar(255) DEFAULT NULL AFTER `mfa_method`;

CREATE TABLE `payments` (
  `id` varchar(191) NOT NULL,
  `order_id` varchar(191) NOT NULL,
  `amount` decimal(12,2) NOT NULL,
  `method` enum('CASH','MOBILE_MONEY','BANK_TRANSFER','CARD') NOT NULL,
  `reference` varchar(191) DEFAULT NULL,
  `notes` varchar(500) DEFAULT NULL,
  `paid_at` datetime(3) NOT NULL,
  `status` enum('RECORDED','VOIDED') NOT NULL DEFAULT 'RECORDED',
  `recorded_by` varchar(191) NOT NULL,
  `voided_by` varchar(191) DEFAULT NULL,
  `voided_at` datetime(3) DEFAULT NULL,
  `void_reason` varchar(500) DEFAULT NULL,
  `created_at` datetime(3) NOT NULL DEFAULT current_timestamp(3),
  `updated_at` datetime(3) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `payments_order_id_idx` (`order_id`),
  KEY `payments_paid_at_idx` (`paid_at`),
  KEY `payments_recorded_by_fkey` (`recorded_by`),
  KEY `payments_voided_by_fkey` (`voided_by`),
  CONSTRAINT `payments_order_id_fkey` FOREIGN KEY (`order_id`) REFERENCES `orders` (`id`) ON UPDATE CASCADE,
  CONSTRAINT `payments_recorded_by_fkey` FOREIGN KEY (`recorded_by`) REFERENCES `users` (`id`) ON UPDATE CASCADE,
  CONSTRAINT `payments_voided_by_fkey` FOREIGN KEY (`voided_by`) REFERENCES `users` (`id`) ON UPDATE CASCADE,
  CONSTRAINT `payments_amount_positive` CHECK (`amount` > 0)
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

-- New permissions (the seed's catalog lists them too). Granted to the seeded roles only; custom
-- roles get them from the Roles screen.
INSERT IGNORE INTO `permissions` (`id`, `key`, `description`, `module`) VALUES
  (UUID(), 'payments.record', 'Record payments against orders', 'payments'),
  (UUID(), 'payments.void', 'Void a recorded payment (kept on record, with a reason)', 'payments'),
  (UUID(), 'settings.manage', 'Configure system settings such as email (SMTP) and SMS (httpSMS) delivery', 'settings');
INSERT IGNORE INTO `role_permissions` (`role_id`, `permission_id`)
  SELECT r.id, p.id FROM `roles` r JOIN `permissions` p ON p.`key` IN ('payments.record', 'payments.void', 'settings.manage')
   WHERE r.name = 'ADMIN';
INSERT IGNORE INTO `role_permissions` (`role_id`, `permission_id`)
  SELECT r.id, p.id FROM `roles` r JOIN `permissions` p ON p.`key` IN ('payments.record', 'payments.void')
   WHERE r.name = 'MANAGER';
