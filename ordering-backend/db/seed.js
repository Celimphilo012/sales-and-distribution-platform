'use strict';

/**
 * Seeds the reference data every install needs: permissions, the system roles and their grants, and
 * the admin user. Idempotent — safe to re-run (role grants are re-synced to the catalog; permissions
 * no longer in the catalog are removed).
 *
 *   npm run seed        (after loading db/schema.sql)
 */
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

const argon2 = require('argon2');
const { createDb } = require('../src/core/db');
const { createModels } = require('../src/core/models');
const { PERMISSION_CATALOG, ROLE_PERMISSION_MAP } = require('../src/catalog/permission-catalog');

async function main() {
  const db = createDb();
  const models = createModels(db);

  try {
    console.log('Seeding permissions...');
    for (const permission of PERMISSION_CATALOG) {
      const existing = await db.one('SELECT id FROM permissions WHERE `key` = ?', [permission.key]);
      if (existing) {
        await db.exec('UPDATE permissions SET description = ?, module = ? WHERE id = ?', [
          permission.description,
          permission.module,
          existing.id,
        ]);
      } else {
        await models.insert('permission', permission);
      }
    }

    console.log('Removing permissions no longer in the catalog...');
    await db.exec('DELETE FROM permissions WHERE `key` NOT IN (?)', [PERMISSION_CATALOG.map((p) => p.key)]);

    console.log('Seeding roles + role_permissions...');
    for (const [roleName, keys] of Object.entries(ROLE_PERMISSION_MAP)) {
      const role =
        (await db.one('SELECT id FROM roles WHERE name = ?', [roleName])) ??
        (await models.insert('role', { name: roleName, description: `${roleName} role`, isSystem: true }));
      const permissions = await db.query('SELECT id FROM permissions WHERE `key` IN (?)', [keys]);
      await db.transaction(async (tx) => {
        await db.exec('DELETE FROM role_permissions WHERE role_id = ?', [role.id], tx);
        await models.insertMany('rolePermission', permissions.map((p) => ({ roleId: role.id, permissionId: p.id })), tx);
      });
    }

    const adminEmail = process.env.SEED_ADMIN_EMAIL ?? 'admin@example.com';
    const adminPassword = process.env.SEED_ADMIN_PASSWORD ?? 'ChangeMe123!';
    console.log(`Seeding admin user (${adminEmail})...`);
    const adminRole = await db.one('SELECT id FROM roles WHERE name = ?', ['ADMIN']);
    const admin =
      (await db.one('SELECT id FROM users WHERE email = ?', [adminEmail])) ??
      (await models.insert('user', {
        email: adminEmail,
        passwordHash: await argon2.hash(adminPassword),
        fullName: 'System Administrator',
        status: 'ACTIVE',
      }));
    await db.exec('INSERT IGNORE INTO user_roles (user_id, role_id) VALUES (?, ?)', [admin.id, adminRole.id]);

    console.log('Seed complete.');
  } finally {
    await db.close();
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
