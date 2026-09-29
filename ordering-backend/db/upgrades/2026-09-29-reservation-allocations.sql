-- =====================================================================================
-- Upgrade an EXISTING distribution_platform to the current schema: per-line stock allocations.
-- Run AFTER 2026-09-29-payments-security-notifications.sql. A fresh install does NOT need this.
--
-- Run ONCE, after a backup:
--   mysqldump -u root distribution_platform > distribution_platform-backup.sql
--   mysql -u root distribution_platform < db/upgrades/2026-09-29-reservation-allocations.sql
--
-- An order line may now be reserved from SEVERAL warehouse locations (e.g. 6 from Shelf A + 4 from
-- Shelf B). `order_item_allocations` records where each line's stock is held (with the location's
-- name as it was when reserved, like order lines snapshot the product name); order_items.
-- reserved_location_id stays as the line's first (primary) location for display. Lines reserved
-- before this upgrade are backfilled with one allocation for their whole quantity.
-- location_id is a warehouse-system id: no foreign key across the system boundary (ARCHITECTURE §A2).
-- =====================================================================================
SET NAMES utf8mb4;

CREATE TABLE `order_item_allocations` (
  `id` varchar(191) NOT NULL,
  `order_item_id` varchar(191) NOT NULL,
  `location_id` varchar(191) NOT NULL,
  `location_label` varchar(191) DEFAULT NULL,
  `quantity` decimal(14,3) NOT NULL,
  `position` int(11) NOT NULL DEFAULT 0,
  `created_at` datetime(3) NOT NULL DEFAULT current_timestamp(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `order_item_allocations_item_location_key` (`order_item_id`,`location_id`),
  CONSTRAINT `order_item_allocations_order_item_id_fkey` FOREIGN KEY (`order_item_id`) REFERENCES `order_items` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `order_item_allocations_quantity_positive` CHECK (`quantity` > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO `order_item_allocations` (`id`, `order_item_id`, `location_id`, `quantity`, `position`, `created_at`)
  SELECT UUID(), i.id, i.reserved_location_id, i.quantity_ordered, 0, UTC_TIMESTAMP(3)
    FROM `order_items` i
   WHERE i.reserved_location_id IS NOT NULL AND i.quantity_ordered > 0;
