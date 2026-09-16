-- DropForeignKey
ALTER TABLE `categories` DROP FOREIGN KEY `categories_parent_id_fkey`;

-- DropForeignKey
ALTER TABLE `inventory_balances` DROP FOREIGN KEY `inventory_balances_location_id_fkey`;

-- DropForeignKey
ALTER TABLE `inventory_balances` DROP FOREIGN KEY `inventory_balances_product_id_fkey`;

-- DropForeignKey
ALTER TABLE `inventory_transactions` DROP FOREIGN KEY `inventory_transactions_from_location_id_fkey`;

-- DropForeignKey
ALTER TABLE `inventory_transactions` DROP FOREIGN KEY `inventory_transactions_performed_by_fkey`;

-- DropForeignKey
ALTER TABLE `inventory_transactions` DROP FOREIGN KEY `inventory_transactions_product_id_fkey`;

-- DropForeignKey
ALTER TABLE `inventory_transactions` DROP FOREIGN KEY `inventory_transactions_to_location_id_fkey`;

-- DropForeignKey
ALTER TABLE `locations` DROP FOREIGN KEY `locations_parent_id_fkey`;

-- DropForeignKey
ALTER TABLE `locations` DROP FOREIGN KEY `locations_warehouse_id_fkey`;

-- DropForeignKey
ALTER TABLE `order_items` DROP FOREIGN KEY `order_items_product_id_fkey`;

-- DropForeignKey
ALTER TABLE `product_images` DROP FOREIGN KEY `product_images_product_id_fkey`;

-- DropForeignKey
ALTER TABLE `products` DROP FOREIGN KEY `products_category_id_fkey`;

-- DropForeignKey
ALTER TABLE `stock_adjustments` DROP FOREIGN KEY `stock_adjustments_location_id_fkey`;

-- DropForeignKey
ALTER TABLE `stock_adjustments` DROP FOREIGN KEY `stock_adjustments_product_id_fkey`;

-- DropForeignKey
ALTER TABLE `stock_adjustments` DROP FOREIGN KEY `stock_adjustments_requested_by_fkey`;

-- DropForeignKey
ALTER TABLE `stock_adjustments` DROP FOREIGN KEY `stock_adjustments_reviewed_by_fkey`;

-- DropForeignKey
ALTER TABLE `stock_count_items` DROP FOREIGN KEY `stock_count_items_location_id_fkey`;

-- DropForeignKey
ALTER TABLE `stock_count_items` DROP FOREIGN KEY `stock_count_items_product_id_fkey`;

-- DropForeignKey
ALTER TABLE `stock_count_items` DROP FOREIGN KEY `stock_count_items_stock_count_id_fkey`;

-- DropForeignKey
ALTER TABLE `stock_counts` DROP FOREIGN KEY `stock_counts_location_id_fkey`;

-- DropForeignKey
ALTER TABLE `stock_counts` DROP FOREIGN KEY `stock_counts_started_by_fkey`;

-- DropForeignKey
ALTER TABLE `stock_counts` DROP FOREIGN KEY `stock_counts_warehouse_id_fkey`;

-- DropTable
DROP TABLE `categories`;

-- DropTable
DROP TABLE `inventory_balances`;

-- DropTable
DROP TABLE `inventory_transactions`;

-- DropTable
DROP TABLE `locations`;

-- DropTable
DROP TABLE `product_images`;

-- DropTable
DROP TABLE `products`;

-- DropTable
DROP TABLE `stock_adjustments`;

-- DropTable
DROP TABLE `stock_count_items`;

-- DropTable
DROP TABLE `stock_counts`;

-- DropTable
DROP TABLE `warehouses`;

