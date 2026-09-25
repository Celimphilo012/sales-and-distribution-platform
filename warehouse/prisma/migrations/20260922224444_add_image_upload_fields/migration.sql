-- AlterTable
ALTER TABLE `product_images` ADD COLUMN `storage_path` VARCHAR(191) NULL,
    MODIFY `url` VARCHAR(191) NULL;

-- AlterTable
ALTER TABLE `workstreams` ADD COLUMN `image_path` VARCHAR(191) NULL;
