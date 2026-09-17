# ARCHITECTURE.md

Inventory, Sales and Distribution Management Platform.

> **ARCHITECTURE CHANGE (business requirement):** The platform is being split into
> **TWO independent systems with SEPARATE databases**, because the ordering/back-office
> side must not share a database with the warehouse. This supersedes the original
> "ONE central database" design below. The original single-database sections (ledger
> model, order lifecycle, location tree, permission matrix, etc.) remain accurate as a
> description of how each concern works **within** its system — they are not deleted,
> because the warehouse system inherits almost all of that logic intact. See the
> **Two-System Split** section for what lives where and the revised roadmap.

**TWO systems · TWO databases · each its own backend/API and its own auth.**

- **Warehouse System** (`/warehouse`, port 3100, db `warehouse_db`) — owns the physical
  stock world AND the product catalogue: products, categories, product-images,
  warehouses, locations (tree), inventory balances, the transaction ledger
  (`applyTransaction`, frozen), receiving, transfers, stock counts, adjustments. Has its
  own auth/users/roles (warehouse staff log in here). Exposes an **API-key-protected
  external API** for other systems to read the catalogue and check/reserve/release/issue
  stock. **Built first.**
- **Back-Office / Ordering System** (`/backend`, port 3000, db `distribution_platform`)
  — the existing system: its own auth/users/roles, customers, orders, order lifecycle,
  sales batches, payments, order-side reports, dashboard. Owns NO inventory tables. Calls
  the Warehouse API (with the shared key) whenever it needs stock. Stores product id +
  a **snapshot** of name/price on each order line, so orders display without a live
  warehouse lookup.

```
        Warehouse Frontend                Back-Office Frontend (Flutter)
                |                                    |
        Warehouse System                   Back-Office / Ordering System
        NestJS · port 3100                 NestJS · port 3000
        db: warehouse_db                   db: distribution_platform
        own auth · the ledger              own auth · orders/customers
                |                                    |
                |<---- API key (catalogue read, ----|
                       reserve/release/issue stock)
        TWO SEPARATE DATABASES — no shared transaction across the boundary
```

**Key consequence of the split:** reserving/issuing stock during the order lifecycle
(1E/1F) is no longer atomic with the order update — the two databases cannot share a
transaction. The order side uses a reserve→confirm→compensate pattern over the API
instead of a single DB transaction. This is the one real cost of the separation and is
inherent to separate databases, not a design flaw.

---

## A. System Architecture

| Layer | Choice | Why |
|---|---|---|
| Backend | Node.js + **NestJS** (TS) | Enforces modular boundaries (modules, guards, DI); first-class RBAC guards; DTO validation. Raw Express would let discipline erode. |
| Database | **MySQL / MariaDB** (XAMPP local) | Self-referencing trees via recursive CTEs (requires MySQL 8.0+ or MariaDB 10.2.2+), transactional integrity for the stock ledger, JSON columns for audit old/new values. |
| ORM | **Prisma** | Typed queries, clean migrations. Use `$queryRaw` for recursive location-tree reads (Prisma has no native recursive CTE). Requires MySQL 8.0+ / MariaDB 10.2.2+ for the recursive query. |
| Auth | JWT access (short-lived) + rotating refresh (hashed) | Standard, revocable. Passwords via **argon2**. |
| Frontend | Flutter + **Riverpod** | One codebase for web/mobile/desktop; Riverpod = compile-safe DI, low boilerplate for a large CRUD app. |

Guard chain on every mutating route: `AuthGuard → PermissionGuard('key')`, plus an
`AuditInterceptor` that records the change.

---

## A2. Two-System Split — ownership, boundary, and roadmap

**Who owns what** (each table lives in exactly ONE database):

| Concern | System | Database |
|---|---|---|
| auth, users, roles, permissions, audit | BOTH (each its own, independent) | each |
| products, categories, product-images (the catalogue) | Warehouse | warehouse_db |
| warehouses, locations (tree) | Warehouse | warehouse_db |
| inventory balances, transaction ledger, applyTransaction | Warehouse | warehouse_db |
| receiving, transfers, stock counts, adjustments | Warehouse | warehouse_db |
| inventory/catalogue/warehouse reports | Warehouse | warehouse_db |
| customers | Back-Office | distribution_platform |
| orders, order items, order status history | Back-Office | distribution_platform |
| sales batches, payments | Back-Office | distribution_platform |
| order reports, dashboard (stitched w/ warehouse API) | Back-Office | distribution_platform |

**The boundary (API-key API on the Warehouse side):** the back-office calls the
warehouse over HTTP with a shared, scoped API key (NOT a user JWT) to: read the
catalogue, check availability, reserve stock, release a reservation, issue/dispatch
stock. What each key may do is configurable (scoped keys). Human warehouse staff use
normal JWT login to the warehouse system; system-to-system calls use the key.

**Cross-boundary rules:**
- No foreign keys across the boundary. `order_items.product_id` is a plain value
  referencing a product in warehouse_db; the back-office trusts the warehouse API and
  handles "product missing/inactive" at call time.
- No shared transaction. Order reservation/issue uses reserve→confirm→compensate over
  the API (the warehouse guarantees all-or-nothing on ITS side and reports success;
  the order side reacts and compensates on failure).
- Order lines store a name/price snapshot so an order displays without a live lookup.

**Revised roadmap (the split):**
1. Scaffold `/warehouse` standalone (own db + own auth). **DONE.**
2. Move warehouse-native modules into `/warehouse` on warehouse_db; verify the ledger
   invariant in its new home. **DONE** (2a catalogue+tree, 2b ledger+ops; trigger and
   invariant verified in warehouse_db).
3. Build the API-key layer on `/warehouse` (scoped keys). **DONE.**
4. Carve `/backend` down to `/ordering`: remove the moved warehouse modules; keep auth/
   users/customers/orders; point at distribution_platform. **DONE** (warehouse tables
   dropped; order↔stock touchpoints stubbed as 501s mapping 1:1 to the warehouse API;
   order_items.product_id is now a plain column, no cross-boundary FK).
5. **Rewire 1E/1F across the API boundary. The real rework.** Fill the step-4 stubs by
   calling the warehouse API (reserve→confirm→compensate). MUST also close two holes that
   step 4 opened/exposed:
   - **PRICING (rule 8 — currently VIOLATED):** `unitPrice` is temporarily client-supplied
     because the catalogue left `/backend`. Step 5 MUST fetch the current price from
     `GET /api/v1/catalogue` at order-line creation and snapshot THAT — never trust the
     client price. This is the top-priority correctness item; it's a live hole until fixed.
   - **NAME SNAPSHOT:** order lines don't snapshot the product name (pre-existing gap).
     Step 5 fetches name + price from the catalogue API at line creation and stores both
     on the line, so an order displays forever without a live lookup (§A2).
   - reserve on APPROVED→STOCK_RESERVED → `POST /api/v1/stock/reserve`; release on cancel →
     `POST /api/v1/stock/release`; issue on dispatch → `POST /api/v1/stock/issue`. Respect
     the 200-with-discriminator contract (check the discriminator, not just HTTP status)
     and idempotency-on-reference. Handle a reserve shortfall (structured short-lines) by
     keeping the order at APPROVED, not advancing.
6. Rewire the frontend: catalogue screens → warehouse API; order screens → ordering API.

**Warehouse external API contract (step 3 — the back-office consumes these):**
- Auth: `X-API-Key` header, scoped keys (`catalogue:read`, `stock:read`, `stock:reserve`,
  `stock:issue`). Raw key stored only as an argon2 hash — shown once at creation.
- Endpoints under `/api/v1/*`: `GET /catalogue`, `POST /stock/availability`,
  `POST /stock/reserve`, `POST /stock/release`, `POST /stock/issue`.
- reserve/release/issue take a batch of lines + a `reference` (the order id), are
  **all-or-none** and **idempotent on reference** (retry-safe).
- **Business outcomes come back as HTTP 200 with a discriminator field**
  (success / insufficient-stock+shortLines / alreadyReleased / alreadyIssued), NOT as
  error status codes — a shortfall is a 200 with structured short-line detail, not a 4xx.
  **Consumers must check the discriminator, not just the HTTP status.**
- Ledger rows from API calls are attributed to a synthetic `system.api` user (non-login)
  to satisfy the frozen `performed_by` FK; the audit log additionally records `api_key_id`.
- all-or-none is delivered as an observable guarantee (pre-check + saga compensation),
  since `applyTransaction` owns its own per-call DB transaction and can't be nested —
  the same constraint the in-app adjustment approval already lives with.

Everything in sections C–O below still describes how each concern works **within** its
system. The ledger model, location tree, order lifecycle, and permission matrix are
inherited by whichever system owns that concern (per the table above) — largely intact
for the warehouse side; the 1E/1F order lifecycle is the part reworked to cross the API
boundary in step 5.

---

## B. Module Structure (NestJS)

```
auth            products         inventory (core)
users           categories       ├ balances
roles           product-images   ├ transactions (ledger)
permissions                      ├ receiving
                warehouses       ├ transfers
customers       locations        ├ counts
orders          (tree)           └ adjustments
sales-batches
payments        fulfilment       reports
                ├ picking        audit
notifications   ├ packing        common (guards,
                └ dispatch        interceptors, tree utils)
```

Rule: `inventory` is the ONLY module that writes `inventory_balances`, and only by
appending an `inventory_transactions` row inside a DB transaction. Orders, receiving,
transfers all call `InventoryService.applyTransaction()`.

---

## C. Use Cases

```
ADMIN ─── manage users/roles/permissions, config, warehouse structure
MANAGER ─ review/approve/reject orders, view team sales, view inventory
WAREHOUSE ─ receive, put-away, transfer, count, adjust, pick, pack, dispatch
CONSULTANT ─ browse catalogue, create customer, create/submit orders (Phase 2)
DRIVER ─── view dispatch list, mark delivered (later)
SUPPLIER ─ referenced entity; portal later
Shared: authenticate, view own profile, receive notifications
```

Every use case maps to a permission string, not a role check.

---

## D. ERD (relationships)

```
users ─< user_roles >─ roles ─< role_permissions >─ permissions

categories ─< products ─< product_images
                 │
warehouses ─< locations (self-ref: parent_id → id)
                 │            │
                 └──── inventory_balances ──┐ (product_id + location_id, unique)
                                            │
                 inventory_transactions ────┘ (append-only ledger)

customers ─< orders ─< order_items >─ products
              │  └─< order_status_history
              │
        sales_batches ─< orders
              │
           payments (order_id; many payments per order)

stock_counts ─< stock_count_items
audit_logs (polymorphic: entity + entity_id)
notifications (user_id)
```

---

## E. Database Schema (core, abridged)

> **API contract notes (confirmed against the real API — clients must handle these):**
> - **Decimal fields: string on READ, number on WRITE (asymmetric).**
>   `selling_price`, `cost_price`, `min_stock_level` come back as JSON strings
>   (`"25.50"`) on GET, but the create/update DTOs expect plain numbers on
>   POST/PATCH. Models must deserialize strings and serialize numbers. (Confirmed
>   in 6b.)
> - **`GET /categories` returns a FLAT list, not a tree** (no recursive-CTE endpoint like
>   locations' `/subtree`). A category-tree UI must build the hierarchy client-side from
>   the flat list. Locations DO have `/locations/:id/subtree` (recursive CTE).

```sql
-- RBAC
roles(id, name UNIQUE, description, is_system bool, created_at, updated_at)
permissions(id, key UNIQUE, description, module)      -- key e.g. 'orders.approve'
role_permissions(role_id, permission_id, PK(role_id,permission_id))
users(id, email UNIQUE, password_hash, full_name, status, created_at, updated_at)
user_roles(user_id, role_id, PK(user_id,role_id))

-- Catalogue
categories(id, name, parent_id NULL, is_active)       -- categories may nest
products(id, sku UNIQUE, name, description, category_id, selling_price NUMERIC(12,2),
         cost_price NUMERIC(12,2) NULL, uom, min_stock_level, status,
         created_at, updated_at)
product_images(id, product_id, url, sort_order, is_primary)

-- Warehouse tree
warehouses(id, name, code UNIQUE, is_active)
locations(id, warehouse_id, parent_id NULL REFERENCES locations(id),
          name, code, location_type, description, is_active, created_at, updated_at)
-- index (warehouse_id, parent_id); unique (warehouse_id, code)

-- Inventory: balances are a cache; transactions are truth
inventory_balances(id, product_id, location_id,
                   on_hand NUMERIC, reserved NUMERIC, damaged NUMERIC,
                   lost NUMERIC, expired NUMERIC,
                   UNIQUE(product_id, location_id))    -- available = on_hand - reserved
inventory_transactions(id, type, product_id,
                       from_location_id NULL, to_location_id NULL,
                       quantity NUMERIC, reason, reference, order_id NULL,
                       performed_by, created_at)        -- APPEND ONLY

-- Sales
customers(id, name, phone, address, location_text, status, notes,
          created_at, updated_at)
sales_batches(id, consultant_id, batch_date, status, submitted_at)
orders(id, order_number UNIQUE, customer_id, consultant_id NULL,
       sales_batch_id NULL, status, payment_status, order_date, delivery_info,
       total NUMERIC, created_at, updated_at)
order_items(id, order_id, product_id, quantity_ordered, quantity_fulfilled,
            unit_price, line_total)   -- partial fulfilment: ordered vs fulfilled per line
order_status_history(id, order_id, from_status, to_status, changed_by, note, created_at)
payments(id, order_id, amount, method, reference, paid_at, status, recorded_by)

-- Stock count
stock_counts(id, warehouse_id, location_id NULL, status, started_by, submitted_at)
stock_count_items(id, stock_count_id, product_id, location_id,
                  expected_qty, counted_qty, difference)

-- Cross-cutting
audit_logs(id, user_id, action, entity, entity_id,
           old_value JSON, new_value JSON, created_at)
notifications(id, user_id, type, payload JSON, read_at NULL, created_at)
```

`inventory_transactions` types: RECEIVE, TRANSFER, ISSUE, SALE, RETURN, ADJUSTMENT,
DAMAGED, LOST, STOCK_COUNT, RESERVATION, RELEASE_RESERVATION.

> **Known limitation (1G):** ADJUSTMENT transactions are not FK-linked to
> `stock_adjustments` rows — the link was never persisted in 1D (frozen code). The
> `/reports/adjustments` report correlates them heuristically by
> (product_id, location_id, quantity, reviewed_by, status). This is ambiguous when
> two adjustments share those values. Clean fix if adjustment reporting becomes
> load-bearing: add a nullable `stock_adjustment_id` to the ADJUSTMENT transaction in
> a later phase.

---

## F. Role & Permission Matrix

Permissions are strings. Roles are bags of permissions. No role name appears in a
code `if` — check `can('key')`.

| permission key | ADMIN | MANAGER | WAREHOUSE | CONSULTANT |
|---|---|---|---|---|
| catalogue.view | ✓ | ✓ | ✓ | ✓ |
| products.manage | ✓ | | | |
| customers.create | ✓ | ✓ | | ✓ |
| orders.create | ✓ | ✓ | | ✓ |
| orders.edit_own_draft | ✓ | | | ✓ |
| orders.submit | ✓ | ✓ | | ✓ |
| orders.approve / reject | ✓ | ✓ | | |
| orders.view_team | ✓ | ✓ | | |
| orders.view_own | ✓ | ✓ | ✓ | ✓ |
| customers.create | ✓ | ✓ | | ✓ |
| customers.view | ✓ | ✓ | | ✓ |
| inventory.view | ✓ | ✓ | ✓ | |
| inventory.receive | ✓ | | ✓ | |
| inventory.transfer | ✓ | | ✓ | |
| inventory.count | ✓ | | ✓ | |
| inventory.adjust.request | ✓ | | ✓ | |
| inventory.adjust.approve | ✓ | ✓ | | |
| fulfilment.pick/pack/dispatch | ✓ | | ✓ | |
| warehouse.structure.view | ✓ | ✓ | ✓ | |
| warehouse.structure.manage | ✓ | | | |
| users.manage / roles.manage | ✓ | | | |
| reports.view | ✓ | ✓ | | |
| audit.view | ✓ | ✓ | | |

Adjustments are two-step: `inventory.adjust.request` (WAREHOUSE) creates a PENDING
adjustment; `inventory.adjust.approve` (MANAGER) applies it. Separation of duties is
enforced in code — the requester cannot approve their own request, even as ADMIN.

---

## G. Warehouse Location Model

Single self-referencing `locations` table, `parent_id → locations.id`, unlimited depth.
`location_type` (WAREHOUSE/ZONE/AISLE/RACK/SHELF/LEVEL/BIN/PALLET/CAGE/ROOM/FLOOR/OTHER)
is a label, not a structural constraint. Subtree read:

```sql
WITH RECURSIVE tree AS (
  SELECT * FROM locations WHERE id = :rootId
  UNION ALL
  SELECT l.* FROM locations l JOIN tree t ON l.parent_id = t.id
) SELECT * FROM tree;
```

"Create 5 levels" is a convenience loop inserting child rows — no schema limit. Admins
can still add/remove levels, add bins, move locations afterwards.

---

## H. Inventory Transaction Model (invariant)

`applyTransaction(tx)` runs in ONE DB transaction:
1. INSERT `inventory_transactions` (the truth)
2. UPDATE `inventory_balances` for the affected location(s)
3. TRANSFER = −qty at from_location, +qty at to_location
4. Commit or roll back BOTH together

`available = on_hand − reserved`. Fulfilment moves quantity between buckets; never
silently overwrites. A DB trigger backstops the "no balance change without a
transaction" rule.

---

## I. Order Lifecycle

```
DRAFT → SUBMITTED → PENDING_APPROVAL → APPROVED
  → STOCK_RESERVED (RESERVATION txns)
  → PICKING → PACKED → READY_FOR_DISPATCH
  → DISPATCHED (ISSUE/SALE txns deduct on_hand) → DELIVERED → COMPLETED

Exceptions: REJECTED, CANCELLED (→ RELEASE_RESERVATION), RETURNED, PARTIALLY_FULFILLED
```

Transitions defined in a config map, not scattered `if`s. `payment_status`
(UNPAID/PARTIAL/PAID) advances independently. Stock deducts at DISPATCH by default
(see Open Decisions).

---

## J. API Structure (domain-oriented, not screen-oriented)

```
/auth/login  /auth/refresh  /auth/logout
/users  /roles  /permissions
/products  /categories  /products/:id/images
/warehouses  /locations  /locations/:id/children  /locations/:id/subtree
/inventory  /inventory/balances?product=  /inventory/transactions
/inventory/receiving  /inventory/transfers  /inventory/counts
/orders  /orders/:id/{submit,approve,reject,reserve,pick,pack,dispatch,cancel}
/customers  /sales-batches  /payments
/reports/*  /audit-logs  /notifications
```

---

## K. Flutter Folder Structure

```
lib/
  core/            (network, auth, error, responsive/, theme)
  shared/          (data_table, form fields, status_badge, dialogs, cards,
                    warehouse_tree, empty/loading/error states)
  features/
    auth/          data/ domain/ presentation/   ← 3 layers per feature
    products/
    warehouses/    (+ warehouse_tree view)
    inventory/     (balances, receiving, transfers, counts, adjustments)
    orders/
    fulfilment/    (picking, packing, dispatch)
    users_roles/
    reports/
    audit/
    dashboard/
  routing/         (go_router, permission-gated routes)
  app.dart
```

Consultant Portal reuses `core`, `shared`, and the `products`/`orders`/`customers`
data + domain layers verbatim; only presentation differs.

---

## L. Responsive UI Strategy

One `ResponsiveLayout(mobile:, tablet:, desktop:)` widget (breakpoints ~<600 /
600–1024 / >1024). Not stretched mobile:

- **Desktop/web:** persistent sidebar + data tables + multi-column dashboard.
- **Tablet:** collapsible rail + card/table hybrid.
- **Mobile:** bottom nav + list/card views + full-screen forms.

Build one set of business widgets; swap only the layout shell and table-vs-card
renderer per breakpoint. Back Office defaults desktop; Consultant Portal defaults mobile.

**Theming (light + dark).** Define two `ThemeData` objects (light and dark) in
`core/theme` with a shared color/typography token set. Every widget pulls colors,
text styles and spacing from `Theme.of(context)` — NO hard-coded `Color(0x...)` or
raw hex anywhere, including reusable widgets (status badges, cards, tables). A
Riverpod `themeMode` provider (light / dark / system) drives `MaterialApp.themeMode`,
and the choice persists across launches (e.g. shared_preferences). A toggle in the
app bar / settings switches it. Because widgets reference tokens, the whole UI flips
automatically with no per-screen work.

---

## M. Phase 1 Roadmap

- **1A** Auth · Users · Roles · Permissions
- **1B** Products · Categories · Images · Pricing
- **1C** Warehouses · Dynamic location tree
- **1D** Inventory balances · Transactions · Receiving · Put-away · Transfers · Counts · Adjustments
- **1E** Orders · Items · Statuses · Reservations
- **1F** Picking · Packing · Dispatch
- **1G** Reports · Audit logs · Dashboard
- **Phase 2** Consultant Portal (offline support later)

Ship and stabilise each sub-phase before starting the next.

---

## N. Open Decisions (confirm with the business before any dependent task)

1. **Stock deduction point** — **DECIDED: at DISPATCH.** on_hand drops when stock
   is physically dispatched. At dispatch, per item: RELEASE_RESERVATION (frees
   reserved) then ISSUE/SALE (deducts on_hand). Built in 1F.
2. **Adjustments** — **DECIDED: manager approval required.** Two-step
   request/approve: `inventory.adjust.request` (WAREHOUSE) + `inventory.adjust.approve`
   (MANAGER), separation of duties enforced (requester ≠ approver, even for ADMIN).
   Built in 1D.
3. **Leaf-only inventory** — **DECIDED: yes.** `assertLeaf()` enforced on every
   inventory operation; non-leaf locations rejected. Built in 1D.
4. **Sales batch** — mandatory grouping, or can consultants submit single orders?
5. **Partial fulfilment / backorders** — **DECIDED: allowed.** Order items track
   `quantity_ordered` vs `quantity_fulfilled` per line; an order can be
   PARTIALLY_FULFILLED. Modeled from the start (Phase 1E) to avoid a retrofit.
6. **Multi-warehouse ordering** — can one order pull from multiple warehouses?
7. **Currency/tax** — SZL (E) only? Any VAT lines on orders?
8. **ORM confirm** — Prisma (typed, raw CTEs) vs TypeORM (native tree entities).
9. **Product deletion** — soft-delete only (status=inactive), since orders/txns
   reference products historically.
10. **Product image storage** — where do `product_images.url` files live? Local
    disk / S3-style bucket / pasted URLs? (Phase 1B.) Local disk is fine for early
    builds; swap to cloud storage at deploy. The `url` field abstracts this, so the
    choice can change without a schema change.

Items 3, 5 and 2 change the schema — lock these first.

---

## Core Principles (never violate)

1. ONE system · ONE central DB · ONE backend/API · TWO UIs
2. Back Office first, Consultant Portal second
3. Role-based access, database-driven, never hard-coded
4. Dynamic warehouse structure — no fixed levels/racks/shelves
5. Inventory is location-aware and fully auditable (ledger)
6. Orders and payments are separate
7. Don't hard-code business rules that may change
8. Backend enforces security; Flutter UI is not a security layer
9. Build modularly; design for future multi-warehouse and offline consultant use
