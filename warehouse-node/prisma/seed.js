"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
require("dotenv/config");
const crypto_1 = require("crypto");
const client_1 = require("@prisma/client");
const argon2 = __importStar(require("argon2"));
const permission_catalog_1 = require("../src/catalog/permission-catalog");
const require_scopes_decorator_1 = require("../src/core/scopes");
const attribute_type_catalog_1 = require("../src/catalog/attribute-type-catalog");
const prisma = new client_1.PrismaClient();
// Never logs in — exists only so `inventory_transactions.performed_by`
// (a NOT NULL FK) has a valid, accountable row for ledger entries an API
// key (not a JWT user) triggers via the external stock API.
const SYSTEM_API_USER_EMAIL = 'system.api@warehouse.internal';
const BACKOFFICE_API_KEY_NAME = 'Back-office integration';
async function main() {
    console.log('Seeding permissions...');
    for (const permission of permission_catalog_1.PERMISSION_CATALOG) {
        await prisma.permission.upsert({
            where: { key: permission.key },
            update: { description: permission.description, module: permission.module },
            create: permission,
        });
    }
    console.log('Seeding roles + role_permissions...');
    for (const [roleName, permissionKeys] of Object.entries(permission_catalog_1.ROLE_PERMISSION_MAP)) {
        const role = await prisma.role.upsert({
            where: { name: roleName },
            update: {},
            create: { name: roleName, description: `${roleName} role`, isSystem: true },
        });
        const permissions = await prisma.permission.findMany({
            where: { key: { in: permissionKeys } },
        });
        await prisma.rolePermission.deleteMany({ where: { roleId: role.id } });
        await prisma.rolePermission.createMany({
            data: permissions.map((p) => ({ roleId: role.id, permissionId: p.id })),
            skipDuplicates: true,
        });
    }
    console.log('Seeding attribute types (Colour, Size, Weight, Brand, Material, Dimensions)...');
    for (const attributeType of attribute_type_catalog_1.ATTRIBUTE_TYPE_CATALOG) {
        await prisma.attributeType.upsert({
            where: { code: attributeType.code },
            update: { name: attributeType.name, dataType: attributeType.dataType, unit: attributeType.unit },
            create: attributeType,
        });
    }
    const adminEmail = process.env.SEED_ADMIN_EMAIL ?? 'warehouse-admin@example.com';
    const adminPassword = process.env.SEED_ADMIN_PASSWORD ?? 'ChangeMe123!';
    console.log(`Seeding admin user (${adminEmail})...`);
    const adminRole = await prisma.role.findUniqueOrThrow({ where: { name: 'ADMIN' } });
    const passwordHash = await argon2.hash(adminPassword);
    const adminUser = await prisma.user.upsert({
        where: { email: adminEmail },
        update: {},
        create: {
            email: adminEmail,
            passwordHash,
            fullName: 'Warehouse Administrator',
            status: 'ACTIVE',
        },
    });
    await prisma.userRole.upsert({
        where: { userId_roleId: { userId: adminUser.id, roleId: adminRole.id } },
        update: {},
        create: { userId: adminUser.id, roleId: adminRole.id },
    });
    console.log('Seeding system API user (for ledger rows an API key triggers)...');
    // A random, never-shared, never-needed password — nobody ever logs in as
    // this user, it exists only to satisfy performed_by's FK.
    const systemPassword = (0, crypto_1.randomBytes)(24).toString('base64url');
    await prisma.user.upsert({
        where: { email: SYSTEM_API_USER_EMAIL },
        update: {},
        create: {
            email: SYSTEM_API_USER_EMAIL,
            passwordHash: await argon2.hash(systemPassword),
            fullName: 'System (API)',
            status: 'ACTIVE',
        },
    });
    const existingKey = await prisma.apiKey.findFirst({ where: { name: BACKOFFICE_API_KEY_NAME } });
    if (existingKey) {
        console.log(`API key "${BACKOFFICE_API_KEY_NAME}" already exists (id ${existingKey.id}) — skipping; the raw key was only ever shown once, at creation.`);
    }
    else {
        console.log(`Seeding back-office API key (all scopes)...`);
        const rawKey = `whk_${(0, crypto_1.randomBytes)(32).toString('base64url')}`;
        const keyHash = await argon2.hash(rawKey);
        const created = await prisma.apiKey.create({
            data: {
                name: BACKOFFICE_API_KEY_NAME,
                keyHash,
                scopes: [...require_scopes_decorator_1.API_KEY_SCOPES],
                createdBy: adminUser.id,
            },
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
}
main()
    .catch((error) => {
    console.error(error);
    process.exitCode = 1;
})
    .finally(async () => {
    await prisma.$disconnect();
});
