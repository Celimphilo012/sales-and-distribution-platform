'use strict';

/**
 * Seeds the reference data every install needs: permissions, the system roles and their grants,
 * attribute types, the admin user, the system API user, and the back-office API key.
 * Idempotent — safe to re-run (existing rows are kept; role grants are re-synced to the catalog).
 *
 *   npm run seed        (after loading db/schema.sql)
 */
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

const { randomBytes } = require('crypto');
const argon2 = require('argon2');
const { createDb } = require('../src/core/db');
const { createModels } = require('../src/core/models');
const { PERMISSION_CATALOG, ROLE_PERMISSION_MAP } = require('../src/catalog/permission-catalog');
const { ATTRIBUTE_TYPE_CATALOG } = require('../src/catalog/attribute-type-catalog');
const { API_KEY_SCOPES } = require('../src/core/scopes');
const { SYSTEM_API_USER_EMAIL } = require('../src/modules/external-api/stock-reservations.service');

const BACKOFFICE_API_KEY_NAME = 'Back-office integration';

async function main() {
  const db = createDb();
  const models = createModels(db);

  /** Returns the row matching `column = value`, creating it from `data` if there is none. */
  async function findOrCreate(model, table, column, value, data) {
    const existing = await db.one(`SELECT id FROM \`${table}\` WHERE \`${column}\` = ?`, [value]);
    return existing ?? models.insert(model, data);
  }

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

    console.log('Seeding roles + role_permissions...');
    for (const [roleName, permissionKeys] of Object.entries(ROLE_PERMISSION_MAP)) {
      const role = await findOrCreate('role', 'roles', 'name', roleName, {
        name: roleName,
        description: `${roleName} role`,
        isSystem: true,
      });
      const permissions = await db.query('SELECT id FROM permissions WHERE `key` IN (?)', [permissionKeys]);
      await db.transaction(async (tx) => {
        await db.exec('DELETE FROM role_permissions WHERE role_id = ?', [role.id], tx);
        await models.insertMany('rolePermission', permissions.map((p) => ({ roleId: role.id, permissionId: p.id })), tx);
      });
    }

    console.log('Seeding attribute types (Colour, Size, Weight, Brand, Material, Dimensions)...');
    for (const attributeType of ATTRIBUTE_TYPE_CATALOG) {
      const existing = await db.one('SELECT id FROM attribute_types WHERE code = ?', [attributeType.code]);
      if (existing) {
        await models.update(
          'attributeType',
          existing.id,
          { name: attributeType.name, dataType: attributeType.dataType, unit: attributeType.unit },
          'Attribute type',
        );
      } else {
        await models.insert('attributeType', attributeType);
      }
    }

    const adminEmail = process.env.SEED_ADMIN_EMAIL ?? 'warehouse-admin@example.com';
    const adminPassword = process.env.SEED_ADMIN_PASSWORD ?? 'ChangeMe123!';
    console.log(`Seeding admin user (${adminEmail})...`);
    const adminRole = await db.one('SELECT id FROM roles WHERE name = ?', ['ADMIN']);
    const adminUser = await findOrCreate('user', 'users', 'email', adminEmail, {
      email: adminEmail,
      passwordHash: await argon2.hash(adminPassword),
      fullName: 'Warehouse Administrator',
      status: 'ACTIVE',
    });
    await db.exec('INSERT IGNORE INTO user_roles (user_id, role_id) VALUES (?, ?)', [adminUser.id, adminRole.id]);

    console.log('Seeding system API user (for ledger rows an API key triggers)...');
    // A random, never-shared, never-needed password — nobody ever logs in as
    // this user, it exists only to satisfy performed_by's FK.
    await findOrCreate('user', 'users', 'email', SYSTEM_API_USER_EMAIL, {
      email: SYSTEM_API_USER_EMAIL,
      passwordHash: await argon2.hash(randomBytes(24).toString('base64url')),
      fullName: 'System (API)',
      status: 'ACTIVE',
    });

    const existingKey = await db.one('SELECT id FROM api_keys WHERE name = ? LIMIT 1', [BACKOFFICE_API_KEY_NAME]);
    if (existingKey) {
      console.log(
        `API key "${BACKOFFICE_API_KEY_NAME}" already exists (id ${existingKey.id}) — skipping; the raw key was only ever shown once, at creation.`,
      );
    } else {
      console.log('Seeding back-office API key (all scopes)...');
      const rawKey = `whk_${randomBytes(32).toString('base64url')}`;
      const created = await models.insert('apiKey', {
        name: BACKOFFICE_API_KEY_NAME,
        keyHash: await argon2.hash(rawKey),
        scopes: [...API_KEY_SCOPES],
        createdBy: adminUser.id,
      });
      console.log('');
      console.log('=================================================================');
      console.log(' BACK-OFFICE API KEY (raw — shown once, configure it into /backend now):');
      console.log(` ${rawKey}`);
      console.log(` key id: ${created.id}`);
      console.log('=================================================================');
      console.log('');
    }

    console.log('Seed complete.');
  } finally {
    await db.close();
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
