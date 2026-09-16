# CLAUDE.md

This is a modular Inventory, Sales and Distribution Management Platform.
The full design lives in `ARCHITECTURE.md` — **read it before writing any code.**

**TWO independent systems, TWO separate databases** (business requirement — the
ordering/back-office side must not share a database with the warehouse):
- **Warehouse System** (`/warehouse`, port 3100, db `warehouse_db`) — owns the
  catalogue (products/categories/images), warehouses, locations, and the inventory
  ledger; has its own auth; exposes an API-key-protected API. **Built first.**
- **Back-Office / Ordering System** (`/backend`, port 3000, db `distribution_platform`)
  — the existing system: own auth, customers, orders, payments. Owns NO inventory;
  calls the Warehouse API (shared key) for stock.

Each system is standalone: its own database, its own auth, no shared code, no
cross-imports, no foreign keys across the boundary, no shared DB transaction. See
`ARCHITECTURE.md` §A2 for what lives where and the split roadmap.

---

## Stack (do not substitute without asking)

- **Backend:** Node.js + NestJS (TypeScript), REST + OpenAPI/Swagger
- **Database:** MySQL / MariaDB (XAMPP local; requires MySQL 8.0+ or MariaDB 10.2.2+ for recursive location-tree CTEs)
- **ORM:** Prisma (use `$queryRaw` for recursive location-tree queries)
- **Auth:** JWT access token (short-lived) + rotating refresh token (stored hashed); passwords hashed with argon2
- **Frontend:** Flutter (web / Android / iOS / desktop), Riverpod for state

---

## Non-negotiable rules

1. **Permissions, not roles, in code.** NEVER write `if (role === 'ADMIN')`.
   Always check permission strings, e.g. `can('orders.approve')`. Roles and
   permissions are database-driven and configurable.

2. **Inventory is a ledger.** Every stock change = an `inventory_transactions`
   row written in the SAME DB transaction as the balance update. NEVER overwrite
   an `inventory_balances` quantity directly. Only the inventory module writes to
   balances, and only via `InventoryService.applyTransaction()`.

3. **Inventory is location-aware.** Model `(product, location, quantity)`, never
   `(product, quantity)`. The same product can exist in multiple locations.

4. **Inventory buckets are distinct:** `on_hand`, `reserved`, `damaged`, `lost`,
   `expired`. `available = on_hand − reserved`. Fulfilment moves quantity between
   buckets; it never silently overwrites.

5. **Locations are a self-referencing tree** (`locations.parent_id → locations.id`)
   with UNLIMITED depth. NEVER hard-code rack/shelf/level/bin counts or a fixed
   hierarchy. `location_type` is a label, not a structural constraint.

6. **Orders and payments are separate lifecycles.** Creating or approving an
   order does NOT mean the customer has paid. `payment_status` advances
   independently from `status`.

7. **State machines live in config,** not scattered `if` statements. Order and
   inventory transitions must be extendable without rewriting logic.

8. **Backend enforces security.** Never rely on Flutter UI restrictions.
   Every mutating route: `AuthGuard → PermissionGuard('key')`, plus an
   `AuditInterceptor` that writes an `audit_logs` row.

9. **Build modularly.** New modules must not require refactoring existing ones.
   No giant files, no tight coupling. Cross-module calls go through services,
   never direct DB reach-ins.

10. **Soft-delete reference data** (products, etc.) via a status flag — orders and
    transactions reference them historically.

11. **No hard-coded colors in Flutter.** Define light + dark `ThemeData` in
    `core/theme` with shared tokens; every widget reads from `Theme.of(context)`.
    A Riverpod `themeMode` provider (light/dark/system) drives the app and persists
    the choice, with a toggle in the UI. The theme flips the whole app automatically.

---

## Current phase

**System split in progress (see ARCHITECTURE.md §A2 roadmap).**
Backend Phase 1 (1A–1G) is complete and verified. Front-end F1+F2 done.
Step 1 of the split (scaffold `/warehouse` standalone) is DONE. `/backend` (the
existing back-office) stays running untouched as the reference system.

Step 5 — rewire 1E/1F across the API boundary — is DONE. `/backend` now has a
single `WarehouseApiClient` (`src/warehouse-api/`) as the sole path to
`/warehouse`, configured via `WAREHOUSE_API_URL`/`WAREHOUSE_API_KEY` in `.env`.
`OrdersService.reserve()`/`cancel()`/`dispatch()` call the warehouse's
`POST /api/v1/stock/{reserve,release,issue}` (reference = order id) instead of
throwing the step-4 stubs, branching on the 200-with-discriminator contract
(never assuming HTTP 200 = success) and distinguishing that from a
network/auth failure (503/502, order left unchanged, safe to retry — reserve/
release/issue are idempotent on reference). Both rule-8 holes are closed:
`buildLineInputs()` fetches each product from the warehouse catalogue and
snapshots name + current sellingPrice server-side; `unitPrice` is no longer
even an accepted field on `OrderItemInputDto` (whitelist-rejected if sent).
`OrderItem` gained `productName` (nullable — never backfilled for pre-step-5
rows) and `reservedLocationId` (set by `reserve()`, since there's no local
ledger any more to recover it from — `dispatch()`'s issue call needs it
verbatim).

**Next: Step 6 — rewire the frontend.** Catalogue screens call the warehouse
API directly; order screens call the ordering API. `/warehouse` (steps 1–3)
and `/backend` (steps 4–5) are both done and untouched by this note.

---

## Open decisions (do NOT silently assume — ask if a task depends on these)

- Stock deduction point: DECIDED: at DISPATCH. on_hand drops when dispatched;
  at dispatch per item RELEASE_RESERVATION then ISSUE/SALE. Built in 1F.
- Adjustments require manager approval? DECIDED: yes — two-step request/approve,
  `inventory.adjust.request` (WAREHOUSE) + `inventory.adjust.approve` (MANAGER),
  separation of duties enforced (no self-approval). Built in 1D.
- Stock only at leaf locations? DECIDED: yes — `assertLeaf()` enforced on all
  inventory operations. Built in 1D.
- Is a sales batch mandatory, or can consultants submit single orders? (Phase 2)
- Partial fulfilment / backorders? DECIDED: yes — order items track
  quantity_ordered vs quantity_fulfilled; orders can be PARTIALLY_FULFILLED. Phase 1E.
- Can one order pull from multiple warehouses?
- Currency/tax: SZL (E) only? Any VAT lines on orders?
- Product image storage: DECIDED for now — URL-only. Backend stores an opaque
  URL string (no file upload, no static serving). Frontend uses a URL field;
  images display when the URL is externally reachable. File UPLOAD (local-disk
  vs cloud bucket) is a deferred phase tied to the deployment decision — not built yet.
