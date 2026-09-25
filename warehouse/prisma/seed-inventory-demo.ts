import 'dotenv/config';
import { NestFactory } from '@nestjs/core';
import { AppModule } from '../src/app.module';
import { PrismaService } from '../src/common/prisma/prisma.service';
import { CategoriesService } from '../src/categories/categories.service';
import { ProductsService } from '../src/products/products.service';
import { WarehousesService } from '../src/warehouses/warehouses.service';
import { LocationsService } from '../src/locations/locations.service';
import { ReceivingService } from '../src/receiving/receiving.service';
import { InventoryService } from '../src/inventory/inventory.service';
import { WorkstreamsService } from '../src/workstreams/workstreams.service';

/**
 * Seeds realistic TEST INVENTORY for the 6d inventory views, entirely
 * through the real write paths (ReceivingService -> InventoryService.
 * applyTransaction, and applyTransaction directly for the RESERVATION leg)
 * — never a direct `inventory_balances` write (rule 2). Kept as a separate
 * script from `prisma/seed.ts` (auth/roles) so it can be re-run on its own.
 *
 * Deliberately self-contained: a dedicated demo warehouse + 3 root-level
 * (hence leaf — assertLeaf requires zero children, which a fresh root
 * location trivially satisfies) locations, rather than reusing another
 * step's test warehouse/tree, so this data's shape doesn't shift if that
 * other test data is later edited or torn down.
 *
 * Idempotent: every RECEIVE/RESERVATION line is tagged with a unique
 * `reference`; re-running skips any line whose reference already has a
 * matching inventory_transactions row instead of re-applying it. Products/
 * category/locations are looked up by their unique code/sku first and only
 * created if missing.
 */

const CATEGORY_NAME = 'Inventory Demo';
const WORKSTREAM_CODE = 'INVDEMO-WS';
const WORKSTREAM_NAME = 'Inventory Demo';
const WAREHOUSE_CODE = 'INV-DEMO-WH';
const WAREHOUSE_NAME = 'Inventory Demo Warehouse';
const ADMIN_EMAIL = process.env.SEED_ADMIN_EMAIL ?? 'warehouse-admin@example.com';

const LOCATIONS = {
  levelA: { code: 'INVDEMO-L1', name: 'Inventory Demo — Level A', locationType: 'LEVEL' },
  levelB: { code: 'INVDEMO-L2', name: 'Inventory Demo — Level B', locationType: 'LEVEL' },
  shelf1: { code: 'INVDEMO-L3', name: 'Inventory Demo — Shelf 1', locationType: 'SHELF' },
} as const;

const PRODUCTS = {
  bodyLotion: {
    sku: 'INVDEMO-BODYLOTION-500ML',
    name: 'Body Lotion 500ml',
    uom: 'EACH',
    sellingPrice: 45.0,
    costPrice: 22.5,
  },
  shampoo: {
    sku: 'INVDEMO-SHAMPOO-400ML',
    name: 'Shampoo 400ml',
    uom: 'EACH',
    sellingPrice: 38.0,
    costPrice: 19.0,
  },
} as const;

async function main() {
  const app = await NestFactory.createApplicationContext(AppModule, { logger: ['error', 'warn'] });

  try {
    const prisma = app.get(PrismaService);
    const categoriesService = app.get(CategoriesService);
    const productsService = app.get(ProductsService);
    const warehousesService = app.get(WarehousesService);
    const workstreamsService = app.get(WorkstreamsService);
    const locationsService = app.get(LocationsService);
    const receivingService = app.get(ReceivingService);
    const inventoryService = app.get(InventoryService);

    const admin = await prisma.user.findUnique({ where: { email: ADMIN_EMAIL } });
    if (!admin) {
      throw new Error(
        `No user found for ${ADMIN_EMAIL} — run "npm run seed" first to create the admin user.`,
      );
    }
    const performedBy = admin.id;

    console.log('Ensuring demo warehouse...');
    let warehouse = await prisma.warehouse.findUnique({ where: { code: WAREHOUSE_CODE } });
    if (!warehouse) {
      warehouse = await warehousesService.create({ name: WAREHOUSE_NAME, code: WAREHOUSE_CODE });
      console.log(`  created warehouse "${WAREHOUSE_NAME}" (${WAREHOUSE_CODE})`);
    } else {
      console.log(`  reusing existing warehouse "${WAREHOUSE_NAME}" (${WAREHOUSE_CODE})`);
    }

    // Workstreams (catalogue-organization layer, added after this script was
    // first written) — self-contained like everything else here, rather than
    // reusing the migration's "General" default workstream.
    console.log('Ensuring demo workstream...');
    let workstream = await prisma.workstream.findUnique({
      where: { warehouseId_code: { warehouseId: warehouse.id, code: WORKSTREAM_CODE } },
    });
    if (!workstream) {
      workstream = await workstreamsService.create({
        warehouseId: warehouse.id,
        name: WORKSTREAM_NAME,
        code: WORKSTREAM_CODE,
      });
      console.log(`  created workstream "${WORKSTREAM_NAME}" (${WORKSTREAM_CODE})`);
    } else {
      console.log(`  reusing existing workstream "${WORKSTREAM_NAME}" (${WORKSTREAM_CODE})`);
    }

    console.log('Ensuring demo category...');
    let category = await prisma.category.findFirst({ where: { name: CATEGORY_NAME } });
    if (!category) {
      category = await categoriesService.create({ name: CATEGORY_NAME, workstreamId: workstream.id }, performedBy);
      console.log(`  created category "${CATEGORY_NAME}"`);
    } else {
      console.log(`  reusing existing category "${CATEGORY_NAME}"`);
    }

    console.log('Ensuring demo leaf locations...');
    const locationIds: Record<keyof typeof LOCATIONS, string> = {} as never;
    for (const [key, def] of Object.entries(LOCATIONS) as [keyof typeof LOCATIONS, (typeof LOCATIONS)[keyof typeof LOCATIONS]][]) {
      let location = await prisma.location.findFirst({
        where: { warehouseId: warehouse.id, code: def.code },
      });
      if (!location) {
        location = await locationsService.create({
          warehouseId: warehouse.id,
          name: def.name,
          code: def.code,
          locationType: def.locationType,
        });
        console.log(`  created location "${def.name}" (${def.code})`);
      } else {
        console.log(`  reusing existing location "${def.name}" (${def.code})`);
      }
      // Confirms it's still a leaf (it always will be here — nothing ever
      // parents another location under these) before any stock touches it,
      // exactly like receiving/reservation callers do in the real app.
      await locationsService.assertLeaf(location.id);
      locationIds[key] = location.id;
    }

    console.log('Ensuring demo products...');
    const productIds: Record<keyof typeof PRODUCTS, string> = {} as never;
    for (const [key, def] of Object.entries(PRODUCTS) as [keyof typeof PRODUCTS, (typeof PRODUCTS)[keyof typeof PRODUCTS]][]) {
      let product = await prisma.product.findUnique({ where: { sku: def.sku } });
      if (!product) {
        product = await productsService.create(
          {
            sku: def.sku,
            name: def.name,
            categoryId: category.id,
            sellingPrice: def.sellingPrice,
            costPrice: def.costPrice,
            uom: def.uom,
          },
          performedBy,
        );
        console.log(`  created product "${def.name}" (${def.sku})`);
      } else {
        console.log(`  reusing existing product "${def.name}" (${def.sku})`);
      }
      productIds[key] = product.id;
    }

    // --- Stock placement -------------------------------------------------
    // Every quantity below goes through the same write path real stock
    // uses: ReceivingService.receive() (RECEIVE -> InventoryService.
    // applyTransaction) or, for the reservation leg, applyTransaction()
    // directly with type RESERVATION — never a direct inventory_balances
    // write. Each line is tagged with a distinct `reference` so re-running
    // this script is a no-op for lines already applied (checked against
    // inventory_transactions, the ledger itself — the source of truth).

    async function receiveOnce(opts: {
      reference: string;
      productId: string;
      toLocationId: string;
      quantity: number;
      label: string;
    }) {
      const existing = await prisma.inventoryTransaction.findFirst({
        where: { type: 'RECEIVE', productId: opts.productId, reference: opts.reference },
      });
      if (existing) {
        console.log(`  [skip] ${opts.label} — reference "${opts.reference}" already applied`);
        return;
      }
      await receivingService.receive(
        {
          supplier: 'Seed — Inventory Demo Data',
          productId: opts.productId,
          toLocationId: opts.toLocationId,
          quantity: opts.quantity,
          reference: opts.reference,
          notes: 'Seeded for 6d inventory view verification.',
        },
        performedBy,
      );
      console.log(`  [applied] ${opts.label}: RECEIVE ${opts.quantity} (ref ${opts.reference})`);
    }

    async function reserveOnce(opts: {
      reference: string;
      productId: string;
      fromLocationId: string;
      quantity: number;
      label: string;
    }) {
      const existing = await prisma.inventoryTransaction.findFirst({
        where: { type: 'RESERVATION', productId: opts.productId, reference: opts.reference },
      });
      if (existing) {
        console.log(`  [skip] ${opts.label} — reference "${opts.reference}" already applied`);
        return;
      }
      await locationsService.assertLeaf(opts.fromLocationId);
      await inventoryService.applyTransaction({
        type: 'RESERVATION',
        productId: opts.productId,
        fromLocationId: opts.fromLocationId,
        quantity: opts.quantity,
        reference: opts.reference,
        reason: 'Seeded for 6d inventory view verification (bucket split demo).',
        performedBy,
      });
      console.log(`  [applied] ${opts.label}: RESERVATION ${opts.quantity} (ref ${opts.reference})`);
    }

    console.log('Placing stock via RECEIVE / RESERVATION transactions...');

    // Flagship scenario: Body Lotion split across two leaf locations,
    // 60 + 40 = 100 total on_hand.
    await receiveOnce({
      reference: 'SEED-INVDEMO-BODYLOTION-RECEIVE-L1',
      productId: productIds.bodyLotion,
      toLocationId: locationIds.levelA,
      quantity: 60,
      label: 'Body Lotion @ Level A',
    });
    await receiveOnce({
      reference: 'SEED-INVDEMO-BODYLOTION-RECEIVE-L2',
      productId: productIds.bodyLotion,
      toLocationId: locationIds.levelB,
      quantity: 40,
      label: 'Body Lotion @ Level B',
    });
    // Non-trivial bucket split: 15 of the 60 at Level A are reserved, so
    // on_hand=60/reserved=15/available=45 there (available=85 overall).
    await reserveOnce({
      reference: 'SEED-INVDEMO-BODYLOTION-RESERVE-L1',
      productId: productIds.bodyLotion,
      fromLocationId: locationIds.levelA,
      quantity: 15,
      label: 'Body Lotion reservation @ Level A',
    });

    // Second product, single location.
    await receiveOnce({
      reference: 'SEED-INVDEMO-SHAMPOO-RECEIVE-L3',
      productId: productIds.shampoo,
      toLocationId: locationIds.shelf1,
      quantity: 25,
      label: 'Shampoo 400ml @ Shelf 1',
    });

    // --- Summary -----------------------------------------------------------
    console.log('');
    console.log('=== Seeded inventory summary ===');
    const balances = await inventoryService.findBalances({});
    const relevantProductIds = new Set(Object.values(productIds));
    for (const b of balances) {
      if (!relevantProductIds.has(b.productId)) continue;
      console.log(
        `${b.product.sku} (${b.product.name}) @ ${b.location.name} [${b.location.code}]: ` +
          `onHand=${b.onHand.toString()} reserved=${b.reserved.toString()} available=${b.available.toString()}`,
      );
    }
    console.log('=================================');
    console.log('Seed complete.');
  } finally {
    await app.close();
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
