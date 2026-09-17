/*
  Warnings:

  - Added the required column `workstream_id` to the `categories` table.

  Categories were, and structurally remain, GLOBAL reference data — the
  `categories` table has no warehouse_id of its own (see schema.prisma), so
  there is no per-category signal to split existing rows across warehouses.
  This migration therefore backfills every pre-existing category onto ONE
  default workstream ("General" / code "GEN") rather than one-per-warehouse.

  The default workstream is attached to whichever warehouse sorts first by
  `code` at the time this migration runs (deterministic, and portable to an
  empty shadow database used to validate this migration — there is no
  meaningful "primary" warehouse in the schema to hardcode an id for). If no
  warehouse exists at all yet, a placeholder one is created so the backfill
  can never fail with an orphaned/missing category. No category is dropped.
*/

-- CreateTable
CREATE TABLE `workstreams` (
    `id` VARCHAR(191) NOT NULL,
    `warehouse_id` VARCHAR(191) NOT NULL,
    `name` VARCHAR(191) NOT NULL,
    `code` VARCHAR(191) NOT NULL,
    `description` VARCHAR(191) NULL,
    `is_active` BOOLEAN NOT NULL DEFAULT true,
    `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    `updated_at` DATETIME(3) NOT NULL,

    INDEX `workstreams_warehouse_id_idx`(`warehouse_id`),
    UNIQUE INDEX `workstreams_warehouse_id_code_key`(`warehouse_id`, `code`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- AddForeignKey
ALTER TABLE `workstreams` ADD CONSTRAINT `workstreams_warehouse_id_fkey` FOREIGN KEY (`warehouse_id`) REFERENCES `warehouses`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;

-- AlterTable: add the column NULLable first so existing rows can be
-- backfilled before the NOT NULL constraint is applied below.
ALTER TABLE `categories` ADD COLUMN `workstream_id` VARCHAR(191) NULL;

-- Fallback: if there are categories to backfill but genuinely no warehouse
-- row exists yet, create one placeholder so the default workstream below has
-- something to attach to. (No-op on a real, already-seeded database.)
INSERT INTO `warehouses` (`id`, `name`, `code`, `is_active`)
SELECT 'a4e2f8b1-3d5c-4a91-9e6f-2b7c8d1a0f33', 'Default Warehouse', 'DEFAULT-WH', true
WHERE EXISTS (SELECT 1 FROM `categories`)
  AND NOT EXISTS (SELECT 1 FROM `warehouses`);

-- Seed the single default workstream every pre-existing category will be
-- backfilled onto, attached to whichever warehouse sorts first by code.
INSERT INTO `workstreams` (`id`, `warehouse_id`, `name`, `code`, `description`, `is_active`, `created_at`, `updated_at`)
SELECT
  'abc48e47-25e4-4e7c-a7ee-987042dd03bb',
  w.id,
  'General',
  'GEN',
  'Default workstream — auto-created by the add_workstreams migration to hold every category that existed before workstreams did.',
  true,
  CURRENT_TIMESTAMP(3),
  CURRENT_TIMESTAMP(3)
FROM `warehouses` w
WHERE EXISTS (SELECT 1 FROM `categories`)
ORDER BY w.code ASC
LIMIT 1;

-- Backfill: every existing category (there is no per-category warehouse
-- signal to do anything smarter with) goes onto the default workstream.
UPDATE `categories`
SET `workstream_id` = 'abc48e47-25e4-4e7c-a7ee-987042dd03bb'
WHERE `workstream_id` IS NULL
  AND EXISTS (SELECT 1 FROM `workstreams` WHERE `id` = 'abc48e47-25e4-4e7c-a7ee-987042dd03bb');

-- Now that every row has a value (or the table was empty to begin with),
-- enforce NOT NULL.
ALTER TABLE `categories` MODIFY COLUMN `workstream_id` VARCHAR(191) NOT NULL;

-- CreateIndex
CREATE INDEX `categories_workstream_id_idx` ON `categories`(`workstream_id`);

-- AddForeignKey
ALTER TABLE `categories` ADD CONSTRAINT `categories_workstream_id_fkey` FOREIGN KEY (`workstream_id`) REFERENCES `workstreams`(`id`) ON DELETE RESTRICT ON UPDATE CASCADE;
