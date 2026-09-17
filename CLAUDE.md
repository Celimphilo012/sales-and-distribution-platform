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

**System split (see ARCHITECTURE.md §A2 roadmap) — backend split DONE.**
Backend Phase 1 (1A–1G) complete. Split steps 1–5 DONE: `/warehouse` is a
standalone system (own db, ledger + trigger verified, scoped API-key external
API), and `/backend` (ordering) is carved down and wired to the warehouse API
across the boundary (reserve/release/issue, pricing hole closed).

**Frontend (step 6 — two separate frontends, one per system):**
- `/warehouse-frontend` — standalone Flutter app for the warehouse (logs into
  warehouse 3100). 6a (foundation) DONE. 6b (Products + Categories) DONE.
  6c (Warehouses + dynamic locations tree) DONE.
  6d (Inventory views — "where is this product" + "what's in this location",
  read-only) DONE; the 6c "stock in location" placeholder is now real.
  6e-1 (Receiving + Transfers) DONE (backend-verified via API; leaf-location
  picker reusable; write→read loop confirmed).
  WORKSTREAMS DONE (warehouse: table + category link + catalogue-API exposure +
  frontend Workstream→Category→sub-category nesting). Catalogue-only, not
  operational.
  PRODUCT ATTRIBUTES DONE (warehouse: defined-types attribute_types catalog +
  product_attributes key-value + catalogue-API exposure + frontend attribute
  fields). Descriptive only, NOT variants — stock still per-product.
  6e-2 (Stock Counts + two-step Stock Adjustments) DONE (backend-verified:
  count→variance→PENDING adjustment→different-user approval→stock moves;
  separation-of-duties enforced UI + backend).
  6f (Admin screens: Users, Roles, Audit Log, Settings incl. API-key mgmt) DONE
  (backend-verified). Users/Roles/Settings-Profile built as a REUSABLE TEMPLATE
  for the ordering app; Settings API-key section is warehouse-only.

  **WAREHOUSE FRONTEND IS COMPLETE** — every nav item is a real screen, backend
  + frontend, one whole system done front to back. Verified via real API calls
  against the warehouse backend with distinct test users throughout (6b–6f);
  a manual browser click-through pass has NOT been done for any phase yet —
  Chrome automation has been unreliable in this environment, so every "DONE"
  above is backend-verified, not visually confirmed. Do that pass when
  convenient, on any phase.

  **Two warehouse BACKEND gaps found in 6f (honestly reported, not faked — fill
  when convenient, neither blocks anything):**
  - No audit-log READ endpoint: the warehouse writes audit_logs (AuditInterceptor)
    but serves none back. The Audit Log screen shows a gap notice. Fix: add
    `GET /audit-logs` (mirror the ordering `/backend` one from 1G, which already
    has this — confirm during the R1 retrofit).
  - No self-service change-password: `PATCH /users/:id` is an admin reset (needs
    users.manage, no current-password check), not "change my own password".
    Settings shows a gap notice. Fix: add a self-service change-password endpoint
    (current + new, verifies current). Check whether `/backend` has this either
    during R1.
- `/frontend` → **being retrofit into `/ordering-frontend` as of step R1** (see
  below) — strip warehouse nav, rewire to `/backend`, bring over the reusable
  Users/Roles/Audit/Settings-Profile template from `/warehouse-frontend`.

**Next: R1 — retrofit `/frontend` into `/ordering-frontend`.** Foundation only
(rename, the two known bug fixes, nav strip + re-point to `/backend` port 3000,
admin-template screens); order/customer feature screens are R2+.

**API characteristic (from 6d):** `/inventory/balances` returns a flat
`location_id` + name/code, NOT the full ancestor path. The frontend resolves the
path client-side by walking the locations tree. Works, but it's N-lookups against
the loaded locations data — a candidate for a future backend improvement (return
the path, or denormalize) if inventory lists grow large. 6e-1/6e-2 reference
locations the same way.

**KNOWN ISSUES — FIXED in `/warehouse-frontend`, being patched into
`/ordering-frontend` at R1** (both bugs were in the original `/frontend` this
was copied from):
1. **ConfirmDialog** — go_router/ShellRoute bug: uses the calling context's
   nested Navigator instead of the root, so confirming a destructive action
   crashes. Fix: `rootNavigator: true`.
2. **AppDataTable** — its mobile/tablet card list used a non-`shrinkWrap`
   ListView, which crashes ("unbounded height") when embedded in an
   already-scrolling ancestor. Fix: `shrinkWrap: true`.

**BACKEND GAP — FIXED:** locations previously had no read/write permission
split (all access, incl. reads, gated behind `warehouse.structure.manage`).
Resolved: `warehouse.structure.view` exists for reads, `.manage` remains for
writes, WAREHOUSE role holds `.view` — confirmed in `warehouse/src/permissions/
constants/permission-catalog.ts`.

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
