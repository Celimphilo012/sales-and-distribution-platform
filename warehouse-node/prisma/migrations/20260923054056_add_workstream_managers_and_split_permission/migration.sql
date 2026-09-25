-- CreateTable
CREATE TABLE `workstream_managers` (
    `id` VARCHAR(191) NOT NULL,
    `user_id` VARCHAR(191) NOT NULL,
    `workstream_id` VARCHAR(191) NOT NULL,
    `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),

    INDEX `workstream_managers_workstream_id_idx`(`workstream_id`),
    UNIQUE INDEX `workstream_managers_user_id_workstream_id_key`(`user_id`, `workstream_id`),
    PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- AddForeignKey
ALTER TABLE `workstream_managers` ADD CONSTRAINT `workstream_managers_user_id_fkey` FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE `workstream_managers` ADD CONSTRAINT `workstream_managers_workstream_id_fkey` FOREIGN KEY (`workstream_id`) REFERENCES `workstreams`(`id`) ON DELETE CASCADE ON UPDATE CASCADE;
