-- Warehouse System database schema (warehouse_db) — the single source of truth.
--
-- There is no ORM and no migration tool. To create a NEW database:
--
--   mysql -u <user> -p -e "CREATE DATABASE warehouse_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
--   mysql -u <user> -p warehouse_db < db/schema.sql
--   npm run seed
--
-- (phpMyAdmin: select the database -> Import -> this file.)
--
-- To CHANGE an existing database: write the ALTER statement(s), run them once by hand against each
-- database (local, then the server), and edit this file in the same commit so a fresh install ends
-- up identical. Nothing records which changes a database already has — keep them in step yourself.
--
-- Requires MySQL 8.0.16+ or MariaDB 10.2.2+ (enforced CHECK constraints; recursive CTEs for the
-- location tree). All DATETIME values are UTC.

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

CREATE TABLE `api_keys` (
  `id` varchar(191) NOT NULL,
  `name` varchar(191) NOT NULL,
  `key_hash` varchar(191) NOT NULL,
  `scopes` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL CHECK (json_valid(`scopes`)),
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` datetime(3) NOT NULL DEFAULT current_timestamp(3),
  `last_used_at` datetime(3) DEFAULT NULL,
  `created_by` varchar(191) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `api_keys_created_by_fkey` (`created_by`),
  CONSTRAINT `api_keys_created_by_fkey` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`) ON UPDATE CASCADE
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

CREATE TABLE `attribute_types` (
  `id` varchar(191) NOT NULL,
  `name` varchar(191) NOT NULL,
  `code` varchar(191) NOT NULL,
  `data_type` enum('TEXT','NUMBER') NOT NULL DEFAULT 'TEXT',
  `unit` varchar(191) DEFAULT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` datetime(3) NOT NULL DEFAULT current_timestamp(3),
  `updated_at` datetime(3) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `attribute_types_code_key` (`code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `audit_logs` (
  `id` varchar(191) NOT NULL,
  `user_id` varchar(191) DEFAULT NULL,
  `action` varchar(191) NOT NULL,
  `entity` varchar(191) NOT NULL,
  `entity_id` varchar(191) DEFAULT NULL,
  `old_value` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`old_value`)),
  `new_value` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`new_value`)),
  `created_at` datetime(3) NOT NULL DEFAULT current_timestamp(3),
  `api_key_id` varchar(191) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `audit_logs_entity_entity_id_idx` (`entity`,`entity_id`),
  KEY `audit_logs_user_id_idx` (`user_id`),
  KEY `audit_logs_api_key_id_idx` (`api_key_id`),
  CONSTRAINT `audit_logs_api_key_id_fkey` FOREIGN KEY (`api_key_id`) REFERENCES `api_keys` (`id`) ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT `audit_logs_user_id_fkey` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `categories` (
  `id` varchar(191) NOT NULL,
  `name` varchar(191) NOT NULL,
  `parent_id` varchar(191) DEFAULT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `workstream_id` varchar(191) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `categories_parent_id_idx` (`parent_id`),
  KEY `categories_workstream_id_idx` (`workstream_id`),
  CONSTRAINT `categories_parent_id_fkey` FOREIGN KEY (`parent_id`) REFERENCES `categories` (`id`) ON UPDATE CASCADE,
  CONSTRAINT `categories_workstream_id_fkey` FOREIGN KEY (`workstream_id`) REFERENCES `workstreams` (`id`) ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `inventory_balances` (
  `id` varchar(191) NOT NULL,
  `product_id` varchar(191) NOT NULL,
  `location_id` varchar(191) NOT NULL,
  `on_hand` decimal(14,3) NOT NULL DEFAULT 0.000,
  `reserved` decimal(14,3) NOT NULL DEFAULT 0.000,
  `damaged` decimal(14,3) NOT NULL DEFAULT 0.000,
  `lost` decimal(14,3) NOT NULL DEFAULT 0.000,
  `expired` decimal(14,3) NOT NULL DEFAULT 0.000,
  PRIMARY KEY (`id`),
  UNIQUE KEY `inventory_balances_product_id_location_id_key` (`product_id`,`location_id`),
  KEY `inventory_balances_location_id_fkey` (`location_id`),
  CONSTRAINT `inventory_balances_location_id_fkey` FOREIGN KEY (`location_id`) REFERENCES `locations` (`id`) ON UPDATE CASCADE,
  CONSTRAINT `inventory_balances_product_id_fkey` FOREIGN KEY (`product_id`) REFERENCES `products` (`id`) ON UPDATE CASCADE,
  CONSTRAINT `inventory_balances_on_hand_nonneg` CHECK (`on_hand` >= 0),
  CONSTRAINT `inventory_balances_reserved_nonneg` CHECK (`reserved` >= 0),
  CONSTRAINT `inventory_balances_damaged_nonneg` CHECK (`damaged` >= 0),
  CONSTRAINT `inventory_balances_lost_nonneg` CHECK (`lost` >= 0),
  CONSTRAINT `inventory_balances_expired_nonneg` CHECK (`expired` >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `inventory_transactions` (
  `id` varchar(191) NOT NULL,
  `type` enum('RECEIVE','TRANSFER','ISSUE','SALE','RETURN','ADJUSTMENT','DAMAGED','LOST','STOCK_COUNT','RESERVATION','RELEASE_RESERVATION') NOT NULL,
  `product_id` varchar(191) NOT NULL,
  `from_location_id` varchar(191) DEFAULT NULL,
  `to_location_id` varchar(191) DEFAULT NULL,
  `quantity` decimal(14,3) NOT NULL,
  `reason` varchar(191) DEFAULT NULL,
  `reference` varchar(191) DEFAULT NULL,
  `order_id` varchar(191) DEFAULT NULL,
  `performed_by` varchar(191) NOT NULL,
  `created_at` datetime(3) NOT NULL DEFAULT current_timestamp(3),
  PRIMARY KEY (`id`),
  KEY `inventory_transactions_product_id_idx` (`product_id`),
  KEY `inventory_transactions_from_location_id_idx` (`from_location_id`),
  KEY `inventory_transactions_to_location_id_idx` (`to_location_id`),
  KEY `inventory_transactions_performed_by_fkey` (`performed_by`),
  CONSTRAINT `inventory_transactions_from_location_id_fkey` FOREIGN KEY (`from_location_id`) REFERENCES `locations` (`id`) ON UPDATE CASCADE,
  CONSTRAINT `inventory_transactions_performed_by_fkey` FOREIGN KEY (`performed_by`) REFERENCES `users` (`id`) ON UPDATE CASCADE,
  CONSTRAINT `inventory_transactions_product_id_fkey` FOREIGN KEY (`product_id`) REFERENCES `products` (`id`) ON UPDATE CASCADE,
  CONSTRAINT `inventory_transactions_to_location_id_fkey` FOREIGN KEY (`to_location_id`) REFERENCES `locations` (`id`) ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `locations` (
  `id` varchar(191) NOT NULL,
  `warehouse_id` varchar(191) NOT NULL,
  `parent_id` varchar(191) DEFAULT NULL,
  `name` varchar(191) NOT NULL,
  `code` varchar(191) NOT NULL,
  `location_type` varchar(191) NOT NULL,
  `description` varchar(191) DEFAULT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` datetime(3) NOT NULL DEFAULT current_timestamp(3),
  `updated_at` datetime(3) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `locations_warehouse_id_code_key` (`warehouse_id`,`code`),
  KEY `locations_warehouse_id_parent_id_idx` (`warehouse_id`,`parent_id`),
  KEY `locations_parent_id_fkey` (`parent_id`),
  CONSTRAINT `locations_parent_id_fkey` FOREIGN KEY (`parent_id`) REFERENCES `locations` (`id`) ON UPDATE CASCADE,
  CONSTRAINT `locations_warehouse_id_fkey` FOREIGN KEY (`warehouse_id`) REFERENCES `warehouses` (`id`) ON UPDATE CASCADE
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

CREATE TABLE `permissions` (
  `id` varchar(191) NOT NULL,
  `key` varchar(191) NOT NULL,
  `description` varchar(191) DEFAULT NULL,
  `module` varchar(191) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `permissions_key_key` (`key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `product_attributes` (
  `id` varchar(191) NOT NULL,
  `product_id` varchar(191) NOT NULL,
  `attribute_type_id` varchar(191) NOT NULL,
  `value` varchar(191) NOT NULL,
  `created_at` datetime(3) NOT NULL DEFAULT current_timestamp(3),
  `updated_at` datetime(3) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `product_attributes_product_id_attribute_type_id_key` (`product_id`,`attribute_type_id`),
  KEY `product_attributes_attribute_type_id_idx` (`attribute_type_id`),
  CONSTRAINT `product_attributes_attribute_type_id_fkey` FOREIGN KEY (`attribute_type_id`) REFERENCES `attribute_types` (`id`) ON UPDATE CASCADE,
  CONSTRAINT `product_attributes_product_id_fkey` FOREIGN KEY (`product_id`) REFERENCES `products` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `product_images` (
  `id` varchar(191) NOT NULL,
  `product_id` varchar(191) NOT NULL,
  `url` varchar(191) DEFAULT NULL,
  `sort_order` int(11) NOT NULL DEFAULT 0,
  `is_primary` tinyint(1) NOT NULL DEFAULT 0,
  `storage_path` varchar(191) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `product_images_product_id_idx` (`product_id`),
  CONSTRAINT `product_images_product_id_fkey` FOREIGN KEY (`product_id`) REFERENCES `products` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `products` (
  `id` varchar(191) NOT NULL,
  `sku` varchar(191) NOT NULL,
  `name` varchar(191) NOT NULL,
  `description` varchar(191) DEFAULT NULL,
  `category_id` varchar(191) NOT NULL,
  `selling_price` decimal(12,2) NOT NULL,
  `cost_price` decimal(12,2) DEFAULT NULL,
  `uom` varchar(191) NOT NULL,
  `min_stock_level` decimal(12,2) NOT NULL DEFAULT 0.00,
  `status` enum('ACTIVE','INACTIVE') NOT NULL DEFAULT 'ACTIVE',
  `created_at` datetime(3) NOT NULL DEFAULT current_timestamp(3),
  `updated_at` datetime(3) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `products_sku_key` (`sku`),
  KEY `products_category_id_idx` (`category_id`),
  CONSTRAINT `products_category_id_fkey` FOREIGN KEY (`category_id`) REFERENCES `categories` (`id`) ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `refresh_tokens` (
  `id` varchar(191) NOT NULL,
  `user_id` varchar(191) NOT NULL,
  `token_hash` varchar(191) NOT NULL,
  `expires_at` datetime(3) NOT NULL,
  `revoked_at` datetime(3) DEFAULT NULL,
  `replaced_by_token_id` varchar(191) DEFAULT NULL,
  `created_at` datetime(3) NOT NULL DEFAULT current_timestamp(3),
  PRIMARY KEY (`id`),
  KEY `refresh_tokens_user_id_idx` (`user_id`),
  CONSTRAINT `refresh_tokens_user_id_fkey` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `role_permissions` (
  `role_id` varchar(191) NOT NULL,
  `permission_id` varchar(191) NOT NULL,
  PRIMARY KEY (`role_id`,`permission_id`),
  KEY `role_permissions_permission_id_fkey` (`permission_id`),
  CONSTRAINT `role_permissions_permission_id_fkey` FOREIGN KEY (`permission_id`) REFERENCES `permissions` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `role_permissions_role_id_fkey` FOREIGN KEY (`role_id`) REFERENCES `roles` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `roles` (
  `id` varchar(191) NOT NULL,
  `name` varchar(191) NOT NULL,
  `description` varchar(191) DEFAULT NULL,
  `is_system` tinyint(1) NOT NULL DEFAULT 0,
  `created_at` datetime(3) NOT NULL DEFAULT current_timestamp(3),
  `updated_at` datetime(3) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `roles_name_key` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `stock_adjustments` (
  `id` varchar(191) NOT NULL,
  `product_id` varchar(191) NOT NULL,
  `location_id` varchar(191) NOT NULL,
  `bucket` enum('ON_HAND','RESERVED','DAMAGED','LOST','EXPIRED') NOT NULL,
  `delta` decimal(14,3) NOT NULL,
  `direction` enum('INCREASE','DECREASE') NOT NULL,
  `reason` varchar(191) NOT NULL,
  `reference` varchar(191) DEFAULT NULL,
  `status` enum('PENDING','APPROVED','REJECTED') NOT NULL DEFAULT 'PENDING',
  `requested_by` varchar(191) NOT NULL,
  `requested_at` datetime(3) NOT NULL DEFAULT current_timestamp(3),
  `reviewed_by` varchar(191) DEFAULT NULL,
  `reviewed_at` datetime(3) DEFAULT NULL,
  `review_note` varchar(191) DEFAULT NULL,
  `photo_path` varchar(191) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `stock_adjustments_product_id_idx` (`product_id`),
  KEY `stock_adjustments_location_id_idx` (`location_id`),
  KEY `stock_adjustments_status_idx` (`status`),
  KEY `stock_adjustments_requested_by_fkey` (`requested_by`),
  KEY `stock_adjustments_reviewed_by_fkey` (`reviewed_by`),
  CONSTRAINT `stock_adjustments_location_id_fkey` FOREIGN KEY (`location_id`) REFERENCES `locations` (`id`) ON UPDATE CASCADE,
  CONSTRAINT `stock_adjustments_product_id_fkey` FOREIGN KEY (`product_id`) REFERENCES `products` (`id`) ON UPDATE CASCADE,
  CONSTRAINT `stock_adjustments_requested_by_fkey` FOREIGN KEY (`requested_by`) REFERENCES `users` (`id`) ON UPDATE CASCADE,
  CONSTRAINT `stock_adjustments_reviewed_by_fkey` FOREIGN KEY (`reviewed_by`) REFERENCES `users` (`id`) ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `stock_count_items` (
  `id` varchar(191) NOT NULL,
  `stock_count_id` varchar(191) NOT NULL,
  `product_id` varchar(191) NOT NULL,
  `location_id` varchar(191) NOT NULL,
  `expected_qty` decimal(14,3) NOT NULL,
  `counted_qty` decimal(14,3) DEFAULT NULL,
  `difference` decimal(14,3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `stock_count_items_stock_count_id_product_id_key` (`stock_count_id`,`product_id`),
  KEY `stock_count_items_stock_count_id_idx` (`stock_count_id`),
  KEY `stock_count_items_product_id_fkey` (`product_id`),
  KEY `stock_count_items_location_id_fkey` (`location_id`),
  CONSTRAINT `stock_count_items_location_id_fkey` FOREIGN KEY (`location_id`) REFERENCES `locations` (`id`) ON UPDATE CASCADE,
  CONSTRAINT `stock_count_items_product_id_fkey` FOREIGN KEY (`product_id`) REFERENCES `products` (`id`) ON UPDATE CASCADE,
  CONSTRAINT `stock_count_items_stock_count_id_fkey` FOREIGN KEY (`stock_count_id`) REFERENCES `stock_counts` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `stock_counts` (
  `id` varchar(191) NOT NULL,
  `warehouse_id` varchar(191) NOT NULL,
  `location_id` varchar(191) NOT NULL,
  `status` enum('OPEN','SUBMITTED') NOT NULL DEFAULT 'OPEN',
  `started_by` varchar(191) NOT NULL,
  `started_at` datetime(3) NOT NULL DEFAULT current_timestamp(3),
  `submitted_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `stock_counts_warehouse_id_idx` (`warehouse_id`),
  KEY `stock_counts_location_id_idx` (`location_id`),
  KEY `stock_counts_started_by_fkey` (`started_by`),
  CONSTRAINT `stock_counts_location_id_fkey` FOREIGN KEY (`location_id`) REFERENCES `locations` (`id`) ON UPDATE CASCADE,
  CONSTRAINT `stock_counts_started_by_fkey` FOREIGN KEY (`started_by`) REFERENCES `users` (`id`) ON UPDATE CASCADE,
  CONSTRAINT `stock_counts_warehouse_id_fkey` FOREIGN KEY (`warehouse_id`) REFERENCES `warehouses` (`id`) ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `stock_reservation_lines` (
  `id` varchar(191) NOT NULL,
  `reservation_id` varchar(191) NOT NULL,
  `product_id` varchar(191) NOT NULL,
  `location_id` varchar(191) NOT NULL,
  `quantity` decimal(14,3) NOT NULL,
  `issued_quantity` decimal(14,3) NOT NULL DEFAULT 0.000,
  PRIMARY KEY (`id`),
  UNIQUE KEY `stock_reservation_lines_reservation_id_product_id_location_i_key` (`reservation_id`,`product_id`,`location_id`),
  KEY `stock_reservation_lines_reservation_id_idx` (`reservation_id`),
  KEY `stock_reservation_lines_product_id_fkey` (`product_id`),
  KEY `stock_reservation_lines_location_id_fkey` (`location_id`),
  CONSTRAINT `stock_reservation_lines_location_id_fkey` FOREIGN KEY (`location_id`) REFERENCES `locations` (`id`) ON UPDATE CASCADE,
  CONSTRAINT `stock_reservation_lines_product_id_fkey` FOREIGN KEY (`product_id`) REFERENCES `products` (`id`) ON UPDATE CASCADE,
  CONSTRAINT `stock_reservation_lines_reservation_id_fkey` FOREIGN KEY (`reservation_id`) REFERENCES `stock_reservations` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `stock_reservations` (
  `id` varchar(191) NOT NULL,
  `reference` varchar(191) NOT NULL,
  `label` varchar(191) DEFAULT NULL,
  `status` enum('RESERVED','RELEASED','ISSUED') NOT NULL DEFAULT 'RESERVED',
  `api_key_id` varchar(191) DEFAULT NULL,
  `created_at` datetime(3) NOT NULL DEFAULT current_timestamp(3),
  `updated_at` datetime(3) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `stock_reservations_reference_key` (`reference`),
  KEY `stock_reservations_api_key_id_fkey` (`api_key_id`),
  CONSTRAINT `stock_reservations_api_key_id_fkey` FOREIGN KEY (`api_key_id`) REFERENCES `api_keys` (`id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `user_roles` (
  `user_id` varchar(191) NOT NULL,
  `role_id` varchar(191) NOT NULL,
  PRIMARY KEY (`user_id`,`role_id`),
  KEY `user_roles_role_id_fkey` (`role_id`),
  CONSTRAINT `user_roles_role_id_fkey` FOREIGN KEY (`role_id`) REFERENCES `roles` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `user_roles_user_id_fkey` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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

CREATE TABLE `users` (
  `id` varchar(191) NOT NULL,
  `email` varchar(191) NOT NULL,
  `password_hash` varchar(191) NOT NULL,
  `full_name` varchar(191) NOT NULL,
  `phone` varchar(32) DEFAULT NULL,
  `notify_channel` enum('EMAIL','SMS','NONE') NOT NULL DEFAULT 'EMAIL',
  `mfa_method` enum('NONE','EMAIL','SMS','TOTP') NOT NULL DEFAULT 'NONE',
  `totp_secret` varchar(255) DEFAULT NULL,
  `status` enum('ACTIVE','INACTIVE','SUSPENDED') NOT NULL DEFAULT 'ACTIVE',
  `created_at` datetime(3) NOT NULL DEFAULT current_timestamp(3),
  `updated_at` datetime(3) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `users_email_key` (`email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `warehouses` (
  `id` varchar(191) NOT NULL,
  `name` varchar(191) NOT NULL,
  `code` varchar(191) NOT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`),
  UNIQUE KEY `warehouses_code_key` (`code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `workstream_managers` (
  `id` varchar(191) NOT NULL,
  `user_id` varchar(191) NOT NULL,
  `workstream_id` varchar(191) NOT NULL,
  `created_at` datetime(3) NOT NULL DEFAULT current_timestamp(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `workstream_managers_user_id_workstream_id_key` (`user_id`,`workstream_id`),
  KEY `workstream_managers_workstream_id_idx` (`workstream_id`),
  CONSTRAINT `workstream_managers_user_id_fkey` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `workstream_managers_workstream_id_fkey` FOREIGN KEY (`workstream_id`) REFERENCES `workstreams` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `workstreams` (
  `id` varchar(191) NOT NULL,
  `warehouse_id` varchar(191) NOT NULL,
  `name` varchar(191) NOT NULL,
  `code` varchar(191) NOT NULL,
  `description` varchar(191) DEFAULT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` datetime(3) NOT NULL DEFAULT current_timestamp(3),
  `updated_at` datetime(3) NOT NULL,
  `image_url` varchar(191) DEFAULT NULL,
  `image_path` varchar(191) DEFAULT NULL,
  `contact_email` varchar(191) DEFAULT NULL,
  `contact_name` varchar(191) DEFAULT NULL,
  `contact_phone` varchar(191) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `workstreams_warehouse_id_code_key` (`warehouse_id`,`code`),
  KEY `workstreams_warehouse_id_idx` (`warehouse_id`),
  CONSTRAINT `workstreams_warehouse_id_fkey` FOREIGN KEY (`warehouse_id`) REFERENCES `warehouses` (`id`) ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS = 1;

-- Rule 2 backstop: block ANY write to inventory_balances that does not go through
-- InventoryService.applyTransaction(), which sets @allow_balance_write = 1 for its own
-- transaction and clears it again before the connection returns to the pool. One trigger per
-- event (MySQL/MariaDB have no combined INSERT OR UPDATE OR DELETE trigger).
DELIMITER ;;
CREATE TRIGGER `trg_inventory_balances_guard_insert`
BEFORE INSERT ON `inventory_balances`
FOR EACH ROW
BEGIN
  IF @allow_balance_write IS NULL OR @allow_balance_write <> 1 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Direct writes to inventory_balances are not allowed; use InventoryService.applyTransaction()';
  END IF;
END;;

CREATE TRIGGER `trg_inventory_balances_guard_update`
BEFORE UPDATE ON `inventory_balances`
FOR EACH ROW
BEGIN
  IF @allow_balance_write IS NULL OR @allow_balance_write <> 1 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Direct writes to inventory_balances are not allowed; use InventoryService.applyTransaction()';
  END IF;
END;;

CREATE TRIGGER `trg_inventory_balances_guard_delete`
BEFORE DELETE ON `inventory_balances`
FOR EACH ROW
BEGIN
  IF @allow_balance_write IS NULL OR @allow_balance_write <> 1 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Direct writes to inventory_balances are not allowed; use InventoryService.applyTransaction()';
  END IF;
END;;
DELIMITER ;
