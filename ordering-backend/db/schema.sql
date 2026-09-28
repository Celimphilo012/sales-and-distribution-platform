-- Back-Office / Ordering System database schema (distribution_platform) — the single source of truth.
--
-- There is no ORM and no migration tool. To create a NEW database:
--
--   mysql -u <user> -p -e "CREATE DATABASE distribution_platform CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
--   mysql -u <user> -p distribution_platform < db/schema.sql
--   npm run seed
--
-- (phpMyAdmin: select the database -> Import -> this file.)
--
-- To CHANGE an existing database: write the ALTER statement(s), run them once by hand against each
-- database (local, then the server), and edit this file in the same commit so a fresh install ends
-- up identical. Nothing records which changes a database already has — keep them in step yourself.
--
-- Products live in the warehouse system's own database: order lines hold a plain product id (no
-- foreign key across the system boundary, ARCHITECTURE.md §A2). All DATETIME values are UTC.

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

CREATE TABLE `audit_logs` (
  `id` varchar(191) NOT NULL,
  `user_id` varchar(191) DEFAULT NULL,
  `action` varchar(191) NOT NULL,
  `entity` varchar(191) NOT NULL,
  `entity_id` varchar(191) DEFAULT NULL,
  `old_value` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`old_value`)),
  `new_value` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`new_value`)),
  `created_at` datetime(3) NOT NULL DEFAULT current_timestamp(3),
  PRIMARY KEY (`id`),
  KEY `audit_logs_entity_entity_id_idx` (`entity`,`entity_id`),
  KEY `audit_logs_user_id_idx` (`user_id`),
  CONSTRAINT `audit_logs_user_id_fkey` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `customers` (
  `id` varchar(191) NOT NULL,
  `name` varchar(191) NOT NULL,
  `phone` varchar(191) DEFAULT NULL,
  `address` varchar(191) DEFAULT NULL,
  `location_text` varchar(191) DEFAULT NULL,
  `status` enum('ACTIVE','INACTIVE') NOT NULL DEFAULT 'ACTIVE',
  `notes` varchar(191) DEFAULT NULL,
  `created_at` datetime(3) NOT NULL DEFAULT current_timestamp(3),
  `updated_at` datetime(3) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `order_items` (
  `id` varchar(191) NOT NULL,
  `order_id` varchar(191) NOT NULL,
  `product_id` varchar(191) NOT NULL,
  `quantity_ordered` decimal(14,3) NOT NULL,
  `quantity_fulfilled` decimal(14,3) NOT NULL DEFAULT 0.000,
  `unit_price` decimal(12,2) NOT NULL,
  `line_total` decimal(12,2) NOT NULL,
  `quantity_packed` decimal(14,3) NOT NULL DEFAULT 0.000,
  `quantity_picked` decimal(14,3) NOT NULL DEFAULT 0.000,
  `product_name` varchar(191) DEFAULT NULL,
  `reserved_location_id` varchar(191) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `order_items_order_id_idx` (`order_id`),
  KEY `order_items_product_id_idx` (`product_id`),
  CONSTRAINT `order_items_order_id_fkey` FOREIGN KEY (`order_id`) REFERENCES `orders` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `order_status_history` (
  `id` varchar(191) NOT NULL,
  `order_id` varchar(191) NOT NULL,
  `from_status` enum('DRAFT','SUBMITTED','PENDING_APPROVAL','APPROVED','STOCK_RESERVED','REJECTED','CANCELLED','PICKING','PACKED','READY_FOR_DISPATCH','DISPATCHED','PARTIALLY_FULFILLED','DELIVERED','COMPLETED') DEFAULT NULL,
  `to_status` enum('DRAFT','SUBMITTED','PENDING_APPROVAL','APPROVED','STOCK_RESERVED','REJECTED','CANCELLED','PICKING','PACKED','READY_FOR_DISPATCH','DISPATCHED','PARTIALLY_FULFILLED','DELIVERED','COMPLETED') NOT NULL,
  `changed_by` varchar(191) NOT NULL,
  `note` varchar(191) DEFAULT NULL,
  `created_at` datetime(3) NOT NULL DEFAULT current_timestamp(3),
  PRIMARY KEY (`id`),
  KEY `order_status_history_order_id_idx` (`order_id`),
  KEY `order_status_history_changed_by_fkey` (`changed_by`),
  CONSTRAINT `order_status_history_changed_by_fkey` FOREIGN KEY (`changed_by`) REFERENCES `users` (`id`) ON UPDATE CASCADE,
  CONSTRAINT `order_status_history_order_id_fkey` FOREIGN KEY (`order_id`) REFERENCES `orders` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `orders` (
  `id` varchar(191) NOT NULL,
  `order_number` varchar(191) NOT NULL,
  `customer_id` varchar(191) NOT NULL,
  `consultant_id` varchar(191) DEFAULT NULL,
  `sales_batch_id` varchar(191) DEFAULT NULL,
  `status` enum('DRAFT','SUBMITTED','PENDING_APPROVAL','APPROVED','STOCK_RESERVED','REJECTED','CANCELLED','PICKING','PACKED','READY_FOR_DISPATCH','DISPATCHED','PARTIALLY_FULFILLED','DELIVERED','COMPLETED') NOT NULL DEFAULT 'DRAFT',
  `payment_status` enum('UNPAID','PARTIAL','PAID') NOT NULL DEFAULT 'UNPAID',
  `order_date` datetime(3) NOT NULL DEFAULT current_timestamp(3),
  `delivery_info` varchar(191) DEFAULT NULL,
  `total` decimal(12,2) NOT NULL DEFAULT 0.00,
  `created_at` datetime(3) NOT NULL DEFAULT current_timestamp(3),
  `updated_at` datetime(3) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `orders_order_number_key` (`order_number`),
  KEY `orders_customer_id_idx` (`customer_id`),
  KEY `orders_consultant_id_idx` (`consultant_id`),
  KEY `orders_status_idx` (`status`),
  CONSTRAINT `orders_consultant_id_fkey` FOREIGN KEY (`consultant_id`) REFERENCES `users` (`id`) ON UPDATE CASCADE,
  CONSTRAINT `orders_customer_id_fkey` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`id`) ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `permissions` (
  `id` varchar(191) NOT NULL,
  `key` varchar(191) NOT NULL,
  `description` varchar(191) DEFAULT NULL,
  `module` varchar(191) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `permissions_key_key` (`key`)
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

CREATE TABLE `user_roles` (
  `user_id` varchar(191) NOT NULL,
  `role_id` varchar(191) NOT NULL,
  PRIMARY KEY (`user_id`,`role_id`),
  KEY `user_roles_role_id_fkey` (`role_id`),
  CONSTRAINT `user_roles_role_id_fkey` FOREIGN KEY (`role_id`) REFERENCES `roles` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `user_roles_user_id_fkey` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `users` (
  `id` varchar(191) NOT NULL,
  `email` varchar(191) NOT NULL,
  `password_hash` varchar(191) NOT NULL,
  `full_name` varchar(191) NOT NULL,
  `status` enum('ACTIVE','INACTIVE','SUSPENDED') NOT NULL DEFAULT 'ACTIVE',
  `created_at` datetime(3) NOT NULL DEFAULT current_timestamp(3),
  `updated_at` datetime(3) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `users_email_key` (`email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS = 1;
