# CLAUDE.md

This is a modular Inventory, Sales and Distribution Management Platform.
The full design lives in `ARCHITECTURE.md` — **read it before writing any code.**

**TWO independent systems, TWO separate databases** (business requirement — the
ordering/back-office side must not share a database with the warehouse):
- **Warehouse System** (`/warehouse-node`, port 3200, db `warehouse_db`) — owns the
  catalogue (products/categories/images), warehouses, locations, and the inventory
  ledger; has its own auth; exposes an API-key-protected API. **Built first.**
  **Active implementation: `/warehouse-node`** (port 3200, same db + API contract) —
  plain JavaScript on Node.js + Express with raw parameterised SQL via mysql2, NO
  ORM. `/warehouse-frontend` talks ONLY to it. The NestJS/Prisma `/warehouse`
  (3100) it replaced was DELETED on 2026-09-29 (in git history before that date). Mentions of
  `/warehouse` in the phase log below are historical.
- **Back-Office / Ordering System** (db `distribution_platform`) — own auth, customers,
  orders, payments. Owns NO inventory; calls the Warehouse API (shared key) for stock.
  **Active implementation: `/ordering-backend`** (port 3300) — plain JavaScript on Node.js +
  Express + mysql2, NO ORM, same API contract. `/ordering-frontend` talks ONLY to it. The
  NestJS/Prisma `/backend` (3000) it replaced was DELETED on 2026-09-29 (in git history before
  that date). Mentions of `/backend` in the phase log below are historical.

Each system is standalone: its own database, its own auth, no shared code, no
cross-imports, no foreign keys across the boundary, no shared DB transaction. See
`ARCHITECTURE.md` §A2 for what lives where and the split roadmap.

---

## Stack (do not substitute without asking)

- **Backend:** Node.js + NestJS (TypeScript), REST + OpenAPI/Swagger
- **Database:** MySQL / MariaDB (XAMPP local; requires MySQL 8.0+ or MariaDB 10.2.2+ for recursive location-tree CTEs)
- **ORM: none** (user's decision, 2026-09-28). Both active backends (`/warehouse-node`,
  `/ordering-backend`) are Express + mysql2 raw SQL (`src/core/db.js` + `src/core/models.js`,
  deliberately duplicated — no shared code across systems). No Prisma remains
  anywhere in the repo (legacy `/warehouse` and `/backend` deleted 2026-09-29). NO migration tool and no migration-tracking table in either
  database: each app's `db/schema.sql` is its whole schema (fresh install = load it, then
  `npm run seed`); a schema change = a hand-run ALTER on each database + the same change edited
  into `schema.sql` in one commit.

**Warehouse security + notifications (2026-09-28, `/warehouse-node` + `/warehouse-frontend`):**
- Warehouse ACCESS is deny-by-default (`user_warehouses`; `warehouse.access.all` for ADMIN;
  `warehouse.access.assign` to manage). Workstream-manager assignments must sit inside it.
  On upgrade every existing user was assigned to every existing warehouse (nobody locked out).
- OTP step-up (428 → code by EMAIL/SMS/authenticator → retry with X-OTP-* headers) on adjustment
  approve/reject, stock-count submit, all deactivations/deletions, API-key revoke, role delete,
  MFA-off. Catalog: `warehouse-node/src/catalog/otp-actions.js`. Frontend: one `OtpInterceptor` +
  dialog handles every protected action automatically.
- Optional sign-in MFA per user: email / SMS / authenticator app (TOTP). Users have `phone`,
  `notify_channel` (EMAIL|SMS|NONE), `mfa_method`.
- Notifications (approval workflow) + all codes go out via SMTP (nodemailer) and httpSMS
  (httpsms.com, texts sent from the org's own Android phone). A warehouse admin configures BOTH in
  the app (Settings → Email & SMS delivery, permission `settings.manage`; stored in `app_settings`,
  password/API key encrypted with SECRETS_ENCRYPTION_KEY, never returned; test-send button). `.env`
  is only the fallback; until real sending is switched on, messages print to the server log.
- Packing screen (`GET /packing`, `packing.view`): open orders' lines per user's warehouses/workstreams;
  the ordering system sends `label` ("ORD-0012 · Customer") with each reserve.
- Verified: warehouse-node 111 tests, warehouse-frontend 94 tests + analyze clean + browser pass
  (MFA setup dialog, OTP prompt → code → retry on a test API key, Users, Packing).

**WAREHOUSE CONSOLE REDESIGN (2026-09-30)** — `/warehouse-frontend` now follows the "Warehouse Console v2"
prototype (`warehouse-frontend/warehouse-prototype`, Nocturne design system): dark-first theme
(`core/theme/nocturne.dart`, light toggle), grouped sidebar / tablet rail / phone bottom bar, and every
collection is one `NxListPage` (`shared/nx/`: stats strip, quick segment, filters + chips, table/list/grid,
state remembered per screen). Forms are `showNxDialog`, detail/work views are `showNxSheet`, feedback is
`NxToast`. Kept beyond the prototype: adjustment evidence PHOTO (request form + shown to the reviewer),
SEARCHABLE product/location pickers everywhere (`NxSelect(searchable: true)`), count drafts kept on the
device until submitted, workstream images/contacts, MFA/contact/delivery settings. Reports: 7 reports built
client-side from live data, exported to PDF (`pdf`) and Excel (`excel`) with the company logo/name from
Settings → Report branding (`/settings/branding`, stored in `app_settings`); pick lists print as PDF.
Backend additions: `locations.capacity` (upgrade `2026-09-30-location-capacity.sql`), `GET /warehouses`
carries `summary {locations, slots, capacity, units, workstreams}`, `GET /workstreams` carries `managers`,
`GET /inventory/transactions` carries `performedByUser` + `limit`. Verified: warehouse-node 116 tests,
warehouse-frontend 84 tests + analyze clean.

**Ordering port DONE (2026-09-28):** `/ordering-backend` — 33/33 read endpoints + error shapes
byte-identical to `/backend` on real data (parity script, removed with `/backend`); 14 integration tests (full lifecycle
against an in-process fake warehouse); `/ordering-frontend` repointed to 3300 (analyze clean, 51
tests, live orders/dashboard load). Also fixed two R3b follow-ons there: 409 insufficient-stock now
carries structured `shortLines`; whitespace-only reject notes are refused. `_prisma_migrations`
dropped from `distribution_platform` (backup taken first).

**ORDERING SIDE COMPLETE (2026-09-29)** — `/ordering-backend` + `/ordering-frontend`:
- **Payments** (user's decisions): methods CASH / MOBILE_MONEY / BANK_TRANSFER / CARD (non-cash needs a
  reference); a mistake is VOIDED (kept, reason + one-time code), never edited/deleted; overpayment
  refused (409 + `balanceDue`); no refunds entry type. `payment_status` is DERIVED from RECORDED payments,
  rewritten in the same transaction under a row lock on the order. No payments on DRAFT/REJECTED/
  CANCELLED; an order with payments can't be cancelled until they are voided. Permissions
  `payments.record` / `payments.void` (ADMIN + MANAGER). Order screen has a Payments panel.
- **Security parity with the warehouse** (copied, not shared): OTP step-up on order approve/reject/
  cancel, payment void, customer/user deactivation, role delete, MFA-off; optional sign-in MFA
  (email/SMS/TOTP); users have phone / notify_channel / mfa_method; notifications (submitted order ->
  `orders.approve` holders; consultant hears approved/rejected/cancelled/dispatched/fully paid);
  admin-set SMTP + httpSMS (`settings.manage`, its own `app_settings`); branded HTML emails.
- **R4 DONE:** Reports screen (orders + payments tabs, period selector) and a real Dashboard (manager
  KPIs incl. collected / still owed / awaiting approval; users without `reports.view` see their own
  latest orders).
- Schema: `db/upgrades/2026-09-29-payments-security-notifications.sql` (verified: old schema + upgrade ==
  fresh schema.sql); applied to local `distribution_platform` (backup taken first).
- Verified: ordering-backend 29 tests, ordering-frontend 63 tests + analyze clean, live endpoints on real
  data, browser pass (dashboard, order payments panel + record dialog validation, reports, settings).
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
  warehouse-node 3200). 6a (foundation) DONE. 6b (Products + Categories) DONE.
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
  + frontend, one whole system done front to back. Stock/catalogue features
  (6b–6e) confirmed via user manual browser click-through (light + dark); 6f
  admin screens backend-verified (do a browser pass on the API-key one-time
  reveal when convenient).

  PRODUCT IMPORT DONE (warehouse: bulk product create/update from an uploaded
  Excel/CSV file — `GET /products/import/template`, `POST /products/import/preview`
  session-staged validation, `POST /products/import/confirm` with defensive
  re-validation + partial success + audit logging; frontend 3-step wizard —
  upload → preview with create/update/reject tables → result — reached from
  the Products screen's "Import products" action). Supplements manual product
  creation, doesn't replace it.

  AUDIT LOG DONE — the gap below is closed: `GET /audit-logs` (`AuditController`/
  `AuditService`, gated `audit.view`) now reads back the rows `AuditInterceptor`
  always wrote. The warehouse-frontend Audit Log screen is a real filterable,
  paginated list (ported from the ordering app's own audit screen, plus an
  `apiKey`-attributed row case the ordering app doesn't have, since the
  warehouse's external API is key-authenticated).

  REPORTS + DASHBOARD DONE — new warehouse backend `reports` module: 4
  `reports.view`-gated GET endpoints (`/reports/low-stock`,
  `/reports/inventory-valuation`, `/reports/stock-movement-summary`,
  `/reports/adjustments-summary`) plus one aggregated `/dashboard` payload for
  the frontend homepage. Every number is a DB-level aggregate (Prisma
  `groupBy`/`count` or a raw `$queryRaw` join — never a full-table fetch summed
  in JS); every number cross-checked against an independently-written query
  against the real DB and matched exactly. `reports.view` is a NEW permission
  (added to the catalog, granted to ADMIN + MANAGER, re-seeded) — the
  warehouse-frontend Dashboard screen (the last placeholder nav item) is real:
  KPI tiles, low-stock + pending-adjustments preview lists that link into the
  existing inventory/adjustments screens, a simple stock-movement bar list (no
  new charting dependency), and a recent-activity feed. Confirmed: 403 for a
  user without `reports.view`, the nav item itself disappears for them too, and
  no GET in this feature writes an `audit_logs` row.

  **One warehouse BACKEND gap remains from 6f (honestly reported, not faked —
  fill when convenient, doesn't block anything):**
  - No self-service change-password: `PATCH /users/:id` is an admin reset (needs
    users.manage, no current-password check), not "change my own password".
    Settings shows a gap notice. Fix: add a self-service change-password endpoint
    (current + new, verifies current).
- `/frontend` — the existing app, becomes the ordering front end; retrofit
  (strip warehouse nav, rewire to `/backend`) is a LATER step.

**Ordering frontend retrofit (`/frontend` → `/ordering-frontend`):**
- R1 (rename + patch the two shared-widget bugs + strip warehouse nav + port the
  Users/Roles/Audit/Settings-Profile admin template, re-pointed at `/backend`)
  DONE.
- R2 (Customers — CRUD, sets the ordering feature-screen pattern) DONE.
  API notes found: write ops all gated by `customers.create` (no separate
  edit/delete key); `customers.view` reads. **`/customers` has NO pagination** —
  returns the full array with search + includeInactive only. Client-side status
  filter built over the boolean. The orders endpoint likely shares this
  no-pagination trait — watch performance/UX in R3/R4 if data grows.
- R3a (Order creation + cross-system catalogue picker + draft management + order
  viewing) DONE. Rule 8 verified across the boundary: prices snapshot from the
  warehouse; client-supplied `unitPrice` hard-rejected (400). Added ONE small
  endpoint to `/backend`: `GET /catalogue` (JWT-guarded, orders.create-gated, thin
  relay over the existing internal WarehouseApiClient). The relayed JSON is
  richer than `/backend`'s stale WarehouseProduct TS interface (already carries
  workstream + attributes) — picker shows them for free.
  **API characteristics found (shape R3b/R4):**
  - `customerId` is IMMUTABLE after order creation (PATCH doesn't accept it).
  - `items` is a full REPLACE on create/update, not add/remove-one-line.
  - `/orders` has NO pagination and NO search — just status + customerId filters
    (matches /customers).
  - The entire lifecycle is already wired on `/backend`
    (submit/approve/reject/reserve/cancel/pick/pack/ready/dispatch/deliver/complete
    all exist as real endpoints) — R3b is purely a UI phase, no backend gaps.
- R3b (Order lifecycle UI: submit → approve/reject → reserve → pick/pack/ready →
  dispatch → deliver → complete + cancel + partial fulfilment) DONE.
  **Full two-system flow verified end-to-end:** happy-path lifecycle through the
  UI + cross-checked against the warehouse (reserve dropped available by 20;
  dispatch dropped on_hand by 20 and cleared the reservation); insufficient stock
  showed structured short-line detail with order + warehouse both unchanged;
  partial pack (3 of 5) → PARTIALLY_FULFILLED; warehouse-down (503) handled
  cleanly on reserve/dispatch/cancel with retries safe (idempotency confirmed).
  Payment status stayed UNPAID throughout. 51 tests pass, flutter analyze clean.

  Small `/backend` change part of R3b: registered `WarehouseLocationsModule` in
  app.module.ts (2 lines) — the module existed but was never registered, so
  `GET /warehouse-locations` was 404. Reserve needs per-line leaf locations and
  the frontend can only reach `/backend`, so this was necessary.

  **Backend-shape follow-ons found in R3b (log; fix when convenient):**
  - Insufficient-stock is 409 with the shortfall flattened into MESSAGE TEXT,
    not a structured JSON body. The UI parses text with a fallback to verbatim
    display — fragile to any message-wording change. Fix: return
    structured `{shortLines: [...]}` on 409.
  - `/backend` accepts a whitespace-only reject note (the UI trims to prevent
    it, but the backend should validate too).
  - Partial-dispatch ledger pattern is RESERVATION → RELEASE_RESERVATION (full) →
    ISSUE (shipped), not release-only-the-remainder as originally described in
    backend 1F verification. Net effect is correct — flagging the discrepancy.

  **Bugs fixed by R3b:** location dropdown truncation (22 locations reading
  identical); **specific WCAG contrast fixes in `/ordering-frontend`**
  (token-level, propagates within that app): three dark-mode containers
  (warning/success/info, ratios 2.35–3.81) fixed to accessible pairs; one
  light-mode warning pair improved 4.52 → 8.55 (was a marginal pass, not a fail).
  `/warehouse-frontend` has its own palette — no port needed.
  `/warehouse-frontend` Products table not scrolling (fixed).

  **WCAG contrast fixes: DONE (2a).** All four target pairs now ≥ 4.5:1:
  - `/ordering-frontend` info tone `0288D1` → `016398` (2.90 → 5.10:1).
  - `/warehouse-frontend` info tone `0088B0` → `006486` (3.30 → 5.47:1 / 2.95 → 4.89:1).
  - `/warehouse-frontend` onInfoContainer `006B8C` → `005F7F` on infoContainer (4.29 → 5.12:1).
  Token-level in each app's `AppSemanticColors`. Dark mode untouched.

- ~~R4 — Order reports + dashboard~~ DONE 2026-09-29 (see "ORDERING SIDE COMPLETE" above).

**Housekeeping status (2a COMPLETE):**
- ~~Test-artifact cleanup across both databases~~ DONE: 21 R3b orders + 6 test
  users deleted from ordering DB; 2 test users deleted from warehouse DB; 2 ledger-referenced
  test users correctly DEACTIVATED (FK-blocked, rule 2). Ambiguous r3-* users
  and 13 phase-seed-looking users KEPT and reported (review yourself).
- ~~WCAG contrast fails~~ DONE (see above).
- Stale dev-server processes: 2a hit real memory pressure (Windows killed 5 dev
  servers during it). Keep only what you need running: MySQL + warehouse-node 3200
  (+ ordering-backend 3300 if needed) + one Flutter app.
- ~~Personal browser click-through of R2/R3a/R3b~~ DONE (limited-user click-through
  confirmed permissions hiding cleanly).

**⚠ Active-data reality found during 2a — reconcile BEFORE any demo:**
- **Body Lotion 500ml (INVDEMO-BODYLOTION-500ML) and "Inventory Demo Warehouse"
  are BOTH INACTIVE.** The flagship "where is this product" spec-demo product is
  currently invisible in default active-only views. It's actually in THREE
  locations (not two as previously believed).
- **Active workstreams are Orijins + Puer** (NOT the General/Retail/Wholesale
  referenced in earlier doc notes — those are all inactive). Real active
  catalogue is PC-001, PC-002, HH-002 in the active warehouse "Mbabane Central
  Distribution" (WH-MB-01, 30 locations).
- **Decision before demo:** reactivate the demo data, use the real active data,
  or both. If the flagship multi-location "where is this product" story is told
  with real active products, may need to seed a real product into a second
  active location via RECEIVE (same discipline as PC-002 restore).

**OPEN DECISION (for R3) — Fulfilment nav:** `fulfilment.pick/pack/dispatch`
permissions exist. R1 did NOT add a top-level "Fulfilment" nav item, treating
pick/pack/dispatch as ACTIONS on an individual order (the simpler default).
Alternative: a dedicated Fulfilment section (a queue of orders ready to
pick/pack/dispatch) for fulfilment staff who work a queue rather than browsing
orders. Decide in R3 based on whether fulfilment is a distinct role/workflow in
the real operation. Default: actions-on-order; add a queue view later if needed.

**Change-password gap also exists on `/backend`** (same as warehouse): PATCH
/users/:id is an admin reset, not self-service. Fill both when convenient.

**API characteristic (from 6d):** `/inventory/balances` returns a flat
`location_id` + name/code, NOT the full ancestor path. The frontend resolves the
path client-side by walking the locations tree. Works, but it's N-lookups against
the loaded locations data — a candidate for a future backend improvement (return
the path, or denormalize) if inventory lists grow large. 6e references locations
the same way.

**KNOWN ISSUES to fix during the `/frontend` retrofit** (shared widgets copied
into `/warehouse-frontend` had bugs fixed there; `/frontend`'s copies were left
untouched and almost certainly share them — patch before building `/frontend`
screens that use them):
1. **ConfirmDialog** — go_router/ShellRoute bug: uses the calling context's
   nested Navigator instead of the root, so confirming a destructive action
   crashes. Fixed in `/warehouse-frontend` with `rootNavigator: true`.
2. **AppDataTable** — its mobile/tablet card list used a non-`shrinkWrap`
   ListView, which crashes ("unbounded height") when embedded in an
   already-scrolling ancestor. Fixed in `/warehouse-frontend` with
   `shrinkWrap: true`.

**BACKEND GAP to fix (warehouse) — locations have no read/write permission
split:** the warehouse warehouses/locations API gates ALL access (incl. reads)
behind `warehouse.structure.manage`. So a user who should VIEW the location tree
but not edit it cannot exist (they 403 before the tree loads). This bites in 6e:
receiving/transfer/count staff need to SEE locations to pick where stock goes,
but seeing them currently requires admin-level structure-manage power. FIX on the
warehouse backend before/at 6e: add a read permission (e.g.
`warehouse.structure.view`) for reading the tree, keep `.manage` for editing,
grant `.view` to the WAREHOUSE role. Until fixed, only structure-managers can see
locations.

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
- Can one order pull from multiple warehouses? DECIDED (2026-09-29): NO — one warehouse per order.
  Reserving is AUTOMATIC: `GET /orders/:id/reservation-proposal` plans it (oldest stock first — FIFO
  by the warehouse's `oldestStockAt` estimate — splitting a line across locations when needed, only
  active locations with available stock); the manager reserves it as is, switches warehouse, or
  adjusts a line. Per-line allocations live in `order_item_allocations` (location name snapshotted);
  dispatch ships from them in plan order. The warehouse still refuses atomically if a location lacks
  the stock. Warehouse endpoint: `POST /api/v1/stock/allocation-options` (scope stock:read).
- Currency/tax: SZL (E) only? Any VAT lines on orders?
- Product image storage: DECIDED for now — URL-only. Backend stores an opaque
  URL string (no file upload, no static serving). Frontend uses a URL field;
  images display when the URL is externally reachable. File UPLOAD (local-disk
  vs cloud bucket) is a deferred phase tied to the deployment decision — not built yet.
