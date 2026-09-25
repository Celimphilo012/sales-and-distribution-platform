-- CreateTable
CREATE TABLE `inventory_balances` (
    `id` VARCHAR(191) NOT NULL,
    `product_id` VARCHAR(191) NOT NULL,
    `location_id` VARCHAR(191) NOT NULL,
    `on_hand` DECIMAL(14, 3) NOT NULL DEFAULT 0,
    `reserved` DECIMAL(14, 3) NOT NULL DEFAULT 0,
    `damaged` DECIMAL(14, 3) NOT NULL DEFAULT 0,
    `lost` DECIMAL(14, 3) NOT NULL DEFAULT 0,
    `expired` DECIMAL(14, 3) NOT NULL DEFAULT 0,

    UNIQUE INDEX `inventory_balances_product_id_location_id_key`(`product_id`, `location_id`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `inventory_transactions` (
    `id` VARCHAR(191) NOT NULL,
    `type` ENUM('RECEIVE', 'TRANSFER', 'ISSUE', 'SALE', 'RETURN', 'ADJUSTMENT', 'DAMAGED', 'LOST', 'STOCK_COUNT', 'RESERVATION', 'RELEASE_RESERVATION') NOT NULL,
    `product_id` VARCHAR(191) NOT NULL,
    `from_location_id` VARCHAR(191) NULL,
    `to_location_id` VARCHAR(191) NULL,
    `quantity` DECIMAL(14, 3) NOT NULL,
    `reason` VARCHAR(191) NULL,
    `reference` VARCHAR(191) NULL,
    `order_id` VARCHAR(191) NULL,
    `performed_by` VARCHAR(191) NOT NULL,
    `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    INDEX `inventory_transactions_product_id_idx`(`product_id`),
    INDEX `inventory_transactions_from_location_id_idx`(`from_location_id`),
    INDEX `inventory_transactions_to_location_id_idx`(`to_location_id`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `stock_adjustments` (
    `id` VARCHAR(191) NOT NULL,
    `product_id` VARCHAR(191) NOT NULL,
    `location_id` VARCHAR(191) NOT NULL,
    `bucket` ENUM('ON_HAND', 'RESERVED', 'DAMAGED', 'LOST', 'EXPIRED') NOT NULL,
    `delta` DECIMAL(14, 3) NOT NULL,
    `direction` ENUM('INCREASE', 'DECREASE') NOT NULL,
    `reason` VARCHAR(191) NOT NULL,
    `reference` VARCHAR(191) NULL,
    `status` ENUM('PENDING', 'APPROVED', 'REJECTED') NOT NULL DEFAULT 'PENDING',
    `requested_by` VARCHAR(191) NOT NULL,
    `requested_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `reviewed_by` VARCHAR(191) NULL,
    `reviewed_at` DATETIME(3) NULL,
    `review_note` VARCHAR(191) NULL,

    INDEX `stock_adjustments_product_id_idx`(`product_id`),
    INDEX `stock_adjustments_location_id_idx`(`location_id`),
    INDEX `stock_adjustments_status_idx`(`status`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `stock_counts` (
    `id` VARCHAR(191) NOT NULL,
    `warehouse_id` VARCHAR(191) NOT NULL,
    `location_id` VARCHAR(191) NOT NULL,
    `status` ENUM('OPEN', 'SUBMITTED') NOT NULL DEFAULT 'OPEN',
    `started_by` VARCHAR(191) NOT NULL,
    `started_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `submitted_at` DATETIME(3) NULL,

    INDEX `stock_counts_warehouse_id_idx`(`warehouse_id`),
    INDEX `stock_counts_location_id_idx`(`location_id`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- CreateTable
CREATE TABLE `stock_count_items` (
    `id` VARCHAR(191) NOT NULL,
    `stock_count_id` VARCHAR(191) NOT NULL,
    `product_id` VARCHAR(191) NOT NULL,
    `location_id` VARCHAR(191) NOT NULL,
    `expected_qty` DECIMAL(14, 3) NOT NULL,
    `counted_qty` DECIMAL(14, 3) NULL,
    `difference` DECIMAL(14, 3) NULL,

    INDEX `stock_count_items_stock_count_id_idx`(`stock_count_id`),
    UNIQUE INDEX `stock_count_items_stock_count_id_product_id_key`(`stock_count_id`, `product_id`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- AddForeignKey
ALTER TABLE `inventory_balances` ADD CONSTRAINT `inventory_balances_product_id_fkey` FOREIGN KEY (`product_id`) REFERENCES `products`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `inventory_balances` ADD CONSTRAINT `inventory_balances_location_id_fkey` FOREIGN KEY (`location_id`) REFERENCES `locations`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `inventory_transactions` ADD CONSTRAINT `inventory_transactions_product_id_fkey` FOREIGN KEY (`product_id`) REFERENCES `products`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `inventory_transactions` ADD CONSTRAINT `inventory_transactions_from_location_id_fkey` FOREIGN KEY (`from_location_id`) REFERENCES `locations`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `inventory_transactions` ADD CONSTRAINT `inventory_transactions_to_location_id_fkey` FOREIGN KEY (`to_location_id`) REFERENCES `locations`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `inventory_transactions` ADD CONSTRAINT `inventory_transactions_performed_by_fkey` FOREIGN KEY (`performed_by`) REFERENCES `users`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `stock_adjustments` ADD CONSTRAINT `stock_adjustments_product_id_fkey` FOREIGN KEY (`product_id`) REFERENCES `products`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `stock_adjustments` ADD CONSTRAINT `stock_adjustments_location_id_fkey` FOREIGN KEY (`location_id`) REFERENCES `locations`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `stock_adjustments` ADD CONSTRAINT `stock_adjustments_requested_by_fkey` FOREIGN KEY (`requested_by`) REFERENCES `users`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `stock_adjustments` ADD CONSTRAINT `stock_adjustments_reviewed_by_fkey` FOREIGN KEY (`reviewed_by`) REFERENCES `users`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `stock_counts` ADD CONSTRAINT `stock_counts_warehouse_id_fkey` FOREIGN KEY (`warehouse_id`) REFERENCES `warehouses`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `stock_counts` ADD CONSTRAINT `stock_counts_location_id_fkey` FOREIGN KEY (`location_id`) REFERENCES `locations`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `stock_counts` ADD CONSTRAINT `stock_counts_started_by_fkey` FOREIGN KEY (`started_by`) REFERENCES `users`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `stock_count_items` ADD CONSTRAINT `stock_count_items_stock_count_id_fkey` FOREIGN KEY (`stock_count_id`) REFERENCES `stock_counts`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `stock_count_items` ADD CONSTRAINT `stock_count_items_product_id_fkey` FOREIGN KEY (`product_id`) REFERENCES `products`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `stock_count_items` ADD CONSTRAINT `stock_count_items_location_id_fkey` FOREIGN KEY (`location_id`) REFERENCES `locations`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- Rule 4: buckets are distinct and never negative. Supported natively as
-- of MariaDB 10.2.1 / MySQL 8.0.16 (enforced, not just parsed-and-ignored
-- like older MySQL 5.x). Moved from /backend's init_mysql migration as-is.
ALTER TABLE `inventory_balances`
  ADD CONSTRAINT `inventory_balances_on_hand_nonneg` CHECK (`on_hand` >= 0),
  ADD CONSTRAINT `inventory_balances_reserved_nonneg` CHECK (`reserved` >= 0),
  ADD CONSTRAINT `inventory_balances_damaged_nonneg` CHECK (`damaged` >= 0),
  ADD CONSTRAINT `inventory_balances_lost_nonneg` CHECK (`lost` >= 0),
  ADD CONSTRAINT `inventory_balances_expired_nonneg` CHECK (`expired` >= 0);

-- Rule 2 / §H backstop: block ANY write to inventory_balances (insert,
-- update, or delete) that doesn't go through InventoryService.applyTransaction().
-- Unlike Postgres's transaction-scoped `SET LOCAL`, MySQL/MariaDB session
-- variables (`SET @var`) are connection-scoped and are NOT reset by
-- COMMIT/ROLLBACK — so applyTransaction() must explicitly reset
-- `@allow_balance_write` in a finally block once it's done, since Prisma's
-- interactive transaction holds one dedicated connection for its whole
-- duration but that connection returns to the pool afterwards and could be
-- reused by unrelated queries. MySQL also requires one trigger per event
-- (no combined "INSERT OR UPDATE OR DELETE" like Postgres), hence three.
-- Moved from /backend's init_mysql migration as-is — same guarantee, now
-- enforced on warehouse_db.
CREATE TRIGGER `trg_inventory_balances_guard_insert`
BEFORE INSERT ON `inventory_balances`
FOR EACH ROW
BEGIN
  IF @allow_balance_write IS NULL OR @allow_balance_write <> 1 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Direct writes to inventory_balances are not allowed; use InventoryService.applyTransaction()';
  END IF;
END;

CREATE TRIGGER `trg_inventory_balances_guard_update`
BEFORE UPDATE ON `inventory_balances`
FOR EACH ROW
BEGIN
  IF @allow_balance_write IS NULL OR @allow_balance_write <> 1 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Direct writes to inventory_balances are not allowed; use InventoryService.applyTransaction()';
  END IF;
END;

CREATE TRIGGER `trg_inventory_balances_guard_delete`
BEFORE DELETE ON `inventory_balances`
FOR EACH ROW
BEGIN
  IF @allow_balance_write IS NULL OR @allow_balance_write <> 1 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Direct writes to inventory_balances are not allowed; use InventoryService.applyTransaction()';
  END IF;
END;
