# Sales & Distribution Platform — Backend API

**Phase 1 backend complete** (1A through 1G) of the Inventory, Sales and
Distribution Management Platform:
**Authentication + Users + Roles + Permissions**,
**Products + Categories + Product Images + Pricing**,
**Warehouses + dynamic location hierarchy**,
**Inventory core ledger** (`inventory_balances` + `inventory_transactions`),
**Receiving, Transfers, Stock Adjustments (2-step approval), Stock Counts**,
**Orders, Order Items, Order Status History, Reservations, Customers**,
**Picking, Packing, Dispatch** — completing the order lifecycle, and
**Reports, Audit Log Viewer, Dashboard** — read-only aggregation over
everything the system already records.

See `ARCHITECTURE.md` for the full system design and `CLAUDE.md` for the
non-negotiable rules this codebase follows (permission-string checks only,
never role-name checks; backend-enforced security; audit logging on every
mutating route; etc).

## Stack

- NestJS (TypeScript) + REST + Swagger/OpenAPI
- MySQL / MariaDB (local via XAMPP) + Prisma — requires MySQL 8.0+ or
  MariaDB 10.2.2+ for recursive CTEs (the location subtree query)
- JWT access tokens (15m) + rotating, hashed refresh tokens
- argon2 password hashing

## What's implemented in this phase

- `auth`, `users`, `roles`, `permissions` modules
- `AuthGuard` — validates the access-token JWT (`@Public()` opts a route out)
- `PermissionGuard` + `@RequirePermissions('key')` — resolves the caller's
  effective permissions via `user_roles → roles → role_permissions →
  permissions` on every check. No code path compares role names.
- `AuditInterceptor` — writes one `audit_logs` row (user, action, entity,
  entity_id, old_value, new_value, timestamp) for every mutating (POST/PUT/
  PATCH/DELETE) request that completes successfully. Sensitive fields
  (password, tokens) are redacted before storage.
- Global `ValidationPipe` (whitelist + transform) and a global exception
  filter that normalises every error into one JSON shape.
- Seed script: `ADMIN` / `MANAGER` / `WAREHOUSE` / `CONSULTANT` roles, the
  full §F permission catalog, and one admin user.
- `categories`, `products`, `product-images` modules, gated by the existing
  `AuthGuard`/`PermissionGuard` using the `catalogue.view` (read) and
  `products.manage` (write) permission keys from §F — no new permission
  keys were needed since Phase 1A already seeded both.
- Products and categories are reference data: `DELETE` never removes a row,
  it flips a status flag (`products.status → INACTIVE`,
  `categories.is_active → false`, rule 10) so historical references from
  later phases (orders, inventory transactions) stay valid. Product images
  are pure media, not historically referenced, so they're hard-deleted.
- Category `parent_id` self-reference supports nesting; updates are
  rejected (409) if they would introduce a cycle.
- Product image storage is intentionally abstracted behind a plain `url`
  string (ARCHITECTURE.md open decision — no upload/storage backend is
  wired up in this phase; `url` can point at an external URL, CDN path, or
  local path without a schema change).
- `warehouses`, `locations` modules, gated end-to-end (reads included) by
  a single `warehouse.structure.manage` permission — §F gives this module
  no separate view key, unlike catalogue's view/manage split.
- `locations` is a self-referencing tree (`parent_id → locations.id`) with
  **no depth limit and no enum for `location_type`** (rule 5) — it's a
  free-form label (`ZONE`, `RACK`, `SHELF`, `BIN`, or anything an admin
  invents) validated only as a non-empty string, never a fixed set.
- The recursive subtree read (`GET /locations/:id/subtree`) is a real
  `WITH RECURSIVE` CTE via `PrismaService.$queryRaw` (§G) — Prisma has no
  native recursive-CTE support — using a tagged-template query so the root
  id is parameterised, never string-concatenated. Returns the root plus
  every descendant, each annotated with its `depth` relative to the root.
- `POST /locations/:id/levels` is the "create N levels" convenience from
  §G: a loop of plain inserts creating `count` sibling locations under a
  parent. `count` is validated as a positive integer but has **no upper
  bound** — the rule is "never hard-code rack/shelf/level/bin counts,"
  not "never let an admin type a big number."
- `POST /locations/:id/move` repositions a location in the tree (separate
  from the generic `PATCH /locations/:id` field edit): rejects moving a
  location into its own subtree (409, cycle) and moving it into a
  different warehouse's tree (400) — a location's `warehouse_id` is fixed
  once created.
- Warehouses and locations are structural reference data: `DELETE`
  deactivates (`is_active → false`, rule 10), never hard-deletes, since
  `inventory_balances` references locations historically.
- **`inventory` module — core ledger only (Phase 1D part 1).**
  `InventoryService.applyTransaction()` is the *only* code path in the
  entire codebase allowed to write `inventory_balances` (rule 2): every
  call writes one `inventory_transactions` row (the truth) and the
  resulting balance delta(s) (the cache) inside a single Prisma
  `$transaction` — both commit or both roll back together (§H). No other
  service, in this module or any other, touches `prisma.inventoryBalance`
  directly.
  - **DB trigger backstop, not just convention.** Three `BEFORE INSERT` /
    `BEFORE UPDATE` / `BEFORE DELETE` triggers on `inventory_balances`
    (MySQL/MariaDB requires one trigger per event — no combined "INSERT OR
    UPDATE OR DELETE" like Postgres) `SIGNAL` a `45000` error unless
    `@allow_balance_write = 1` is set on the current session.
    `applyTransaction()` sets that flag as the first statement inside its
    `$transaction` and clears it in a `finally` block before returning.
    That explicit reset matters on MySQL specifically: unlike Postgres's
    transaction-scoped `SET LOCAL` (which auto-resets at COMMIT/ROLLBACK),
    MySQL session variables are connection-scoped and survive both — and
    Prisma returns the transaction's dedicated connection to its pool
    afterwards, where an unrelated later query could otherwise inherit the
    flag. Verified live: a raw `mysql` client `INSERT` against
    `inventory_balances` is rejected even as `root`, both before and
    immediately after a real `applyTransaction()` call completes.
  - **Buckets are distinct and never negative** (rule 4): `on_hand`,
    `reserved`, `damaged`, `lost`, `expired`, each CHECK-constrained
    `>= 0` at the DB level. `available` is never stored — every read
    computes `on_hand - reserved`.
  - **Location-aware** (rule 3): every balance row is `(product_id,
    location_id, ...)`, unique per pair — the same product can sit at any
    number of locations simultaneously.
  - **Type → bucket-effect mapping lives in one config function**
    (`resolveBucketDeltas`, rule 7), not scattered `if`s: `RECEIVE`/
    `RETURN` add to `on_hand` at `toLocationId`; `ISSUE`/`SALE` subtract
    from `on_hand` at `fromLocationId`; `TRANSFER` does both atomically
    across two locations; `DAMAGED`/`LOST` move the same location's stock
    from `on_hand` into `damaged`/`lost`; `RESERVATION`/
    `RELEASE_RESERVATION` only touch the `reserved` bucket, leaving
    `on_hand` untouched (reserving stock never physically moves it); and
    `ADJUSTMENT`/`STOCK_COUNT` are the generic correction path — caller
    picks the bucket (default `on_hand`) and direction. There's no
    dedicated `EXPIRE` transaction type in the §E type list, so the
    `expired` bucket is corrected the same generic way:
    `type: ADJUSTMENT, bucket: 'expired'`.
  - `GET /inventory/balances` (`?productId=&locationId=&warehouseId=`,
    each row includes computed `available`) and `GET
    /inventory/transactions` (`?productId=&locationId=&type=&from=&to=`),
    both guarded by `inventory.view`.
  - The engine (all 11 transaction types, the config-driven bucket
    mapping, the atomic-rollback-on-failure guarantee, and the trigger
    backstop) was exercised end-to-end via `InventoryService` directly
    against the real MySQL/MariaDB instance before this delivery, including
    confirming a failed transaction (e.g. issuing from a location with no
    balance) leaves neither a ledger row nor a partial balance row behind.
  - The recursive subtree query (`WITH RECURSIVE`) runs as-is on
    MySQL/MariaDB with no syntax changes from the Postgres version — both
    dialects accept the same form here. Verified live against a real
    4-level-deep tree (see the location model note in the previous
    section).
- **Phase 1D part 2 — receiving, transfers, stock adjustments, stock
  counts.** Every one of these calls `InventoryService.applyTransaction()`
  (the frozen part-1 engine — untouched) rather than writing
  `inventory_balances` itself; rule 2 holds across the whole module.
  - **Leaf-location policy (resolves Open Decision #3):** every location a
    receive, transfer, adjustment, or count touches must have zero child
    locations. `LocationsService.assertLeaf()` (new, small addition to the
    Phase 1C module) enforces this everywhere stock can move; it's a
    policy that applies to *inventory operations*, not a structural limit
    on `locations` itself — `LocationsController` still has no opinion on
    where stock may sit.
  - `receiving`, `transfers` have no dedicated table — they call
    `applyTransaction()` directly and the resulting `inventory_transactions`
    row *is* their record (`POST /inventory/receiving`: `inventory.receive`,
    `RECEIVE` at `toLocationId`; `POST /inventory/transfers`:
    `inventory.transfer`, one `TRANSFER`). `inventory_transactions` has no
    columns for receiving's `supplier`/`notes`/`receivedDate` — they're
    folded into the ledger row's free-text `reason`; `reference` stays a
    pure doc/PO number. "Receiving user" is always the authenticated
    caller (`performedBy`), never a client-supplied field.
  - **`stock_adjustments` — two-step approval (resolves Open Decision #2).**
    A request (`POST /inventory/adjustments`, `inventory.adjust.request`,
    reason mandatory) only ever creates a `PENDING` row — zero ledger
    effect, `applyTransaction()` is not called. Only `POST
    /inventory/adjustments/:id/approve` (`inventory.adjust.approve`) calls
    it, mapping the row's `bucket`/`direction` onto
    `to`/`fromLocationId` + `bucket` and setting `performedBy` to the
    *approver*; `POST /inventory/adjustments/:id/reject` (same permission,
    `reviewNote` mandatory) never touches stock. **Separation of duties**
    is enforced in `StockAdjustmentsService.approve()`: `reviewedBy ===
    requestedBy` is rejected with 403, even for a user (e.g. ADMIN) who
    holds both permissions — the permission grant and the per-request
    identity check are independent layers. `GET /inventory/adjustments`
    (`?status=`) is gated by `inventory.view`, which happens to be exactly
    the set of roles (ADMIN/MANAGER/WAREHOUSE) that need visibility here.
  - **`stock_counts`.** `POST /inventory/counts` (`inventory.count`)
    snapshots `expected_qty` = current `on_hand` for every product at a
    leaf location (or an explicit `productIds` subset) into
    `stock_count_items`. `PATCH /inventory/counts/:id` (same permission)
    accepts counted quantities for *exactly* the snapshotted product set
    (rejects missing/extra with 400), computes `difference` per item, and
    — for every nonzero difference — creates a `PENDING` `stock_adjustment`
    (`bucket: ON_HAND`, `reason: 'stock count'`, `reference: <count id>`)
    through the exact same `StockAdjustmentsService.createRequest()` used
    by the manual endpoint. The count itself never moves stock; approving
    the resulting adjustment (§3 above) is what does, and is the only
    place that does.
  - **Not nested in one DB transaction.** `applyTransaction()`'s
    `$transaction` is self-contained and Phase 1D part 1 is frozen, so it
    can't be extended to accept an outer `tx`. Approval and count-submit
    therefore do the ledger write *first* (atomic on its own, and the
    thing rule 2 actually cares about), then a separate sequential update
    to `stock_adjustments`/`stock_counts` bookkeeping. A failure in that
    second write is a recoverable inconsistency (stale status on an
    already-correct ledger), not a ledger-integrity violation — documented
    inline in both services.
  - Verified live end-to-end: receive raises `on_hand`; transfer moves
    both legs atomically; a request creates `PENDING` with zero balance
    change; a different-user approval moves stock and writes the
    `ADJUSTMENT` transaction; self-approval is rejected (403) even from an
    ADMIN account holding both permissions; reject requires `reviewNote`
    and moves nothing; a count with a counted qty 5 under expected creates
    a `PENDING` adjustment (`direction: DECREASE`) that only moves stock
    once approved; non-leaf locations are rejected (400) on every one of
    receiving/transfer/adjustment/count; double-approve and double-submit
    are rejected (409); a direct `inventory_balances` write is still
    blocked by the part-1 trigger; every mutation (request/approve/reject/
    count-start/count-submit) wrote an `audit_logs` row via the unmodified
    global `AuditInterceptor`.
- **Phase 1E — orders, order items, order status history, reservations,
  customers.** Stops at `STOCK_RESERVED` on purpose — picking, packing and
  dispatch (§I) are 1F and not modeled (no `PICKING`/`PACKED`/... values in
  the `OrderStatus` enum). Reservation is the only way this phase touches
  inventory, and it goes through the frozen Phase 1D
  `InventoryService.applyTransaction()` exactly like every other module —
  nothing here writes `inventory_balances` directly.
  - **State machine is one config map** (`ORDER_STATUS_TRANSITIONS`, rule
    7), not scattered `if`s: `DRAFT → SUBMITTED → PENDING_APPROVAL →
    APPROVED → STOCK_RESERVED`, with `CANCELLED` reachable from every
    non-terminal state and `REJECTED` only from `PENDING_APPROVAL`. Every
    hop is validated against the map and writes its own
    `order_status_history` row — `POST /orders/:id/submit` performs the
    `DRAFT→SUBMITTED` and `SUBMITTED→PENDING_APPROVAL` hops back-to-back
    in one DB transaction (one user action, two history rows), matching
    how the task names both arrows for that one endpoint.
  - **`payment_status` is untouched by any status transition** (rule 6) —
    it's seeded `UNPAID` at creation and nothing in this phase (there's no
    payments module yet) ever changes it; verified live across the full
    `DRAFT→...→STOCK_RESERVED→CANCELLED` path.
  - **Pricing is never client-supplied.** `unit_price` is snapshotted from
    the product's current `selling_price` at order-creation (and
    draft-edit) time; the client sends `productId` + `quantity` only.
    `line_total`/`total` are computed server-side. Ordering an inactive
    product is rejected.
  - **`PATCH /orders/:id`** is DRAFT-only *and* owner-only: verified live
    that a different consultant gets 403 editing someone else's draft,
    the owner can, and editing a non-DRAFT order is rejected (409)
    regardless of who's asking. Items, when provided, replace the full set
    (delete + recreate), recomputing prices and `total` from current
    catalogue prices — same "replace, don't patch individual rows"
    convention as `PUT /roles/:id/permissions`.
  - **`GET /orders` / `GET /orders/:id` scoping.** Same OR-permission
    problem as Phase 1D part 2's adjustments list: `PermissionGuard` is
    AND-only across its declared keys, so it can't express "view_own OR
    view_team" in the decorator. The route requires the minimal common key
    (`orders.view_own`, held by every role with any order visibility);
    `OrdersService.hasPermission()` then checks `orders.view_team`
    in-service (same query shape `PermissionGuard` itself runs) to decide
    whether to widen the query, or scope it to `consultantId = caller`. A
    single order outside the caller's own scope 404s rather than 403s, so
    a `view_own`-only caller can't probe for the existence of orders they
    can't see.
  - **`consultant_id` is always `req.user.id`**, never client-supplied —
    same "backend derives the actor, the client doesn't" rule as
    `performedBy` throughout Phase 1D. `orders.create` is granted to
    ADMIN/MANAGER/CONSULTANT (§F); whoever creates an order becomes its
    owner for `orders.edit_own_draft` purposes regardless of which
    permission actually let them create it — deliberately not branching on
    role name (rule 1) to decide ownership.
  - **`POST /orders/:id/reserve` — all-or-nothing across multiple
    `applyTransaction()` calls it can't wrap in one DB transaction**
    (same constraint as Phase 1D part 2's approve/count-submit: the frozen
    engine's `$transaction` is self-contained). Every allocation's
    `available = on_hand - reserved` is checked *before* any reservation
    call, so the common case is genuinely all-or-nothing with zero
    side effects on a shortfall — verified live: one satisfiable item +
    one zero-stock item rejects the whole request (409) and leaves the
    *other* item's `reserved` bucket untouched. A real mid-loop race
    (rare, since the pre-check already passed) is handled by compensating
    — releasing everything already reserved in that call — before
    rejecting, so an order is never left half-reserved. Multi-warehouse
    pulling (Open Decision #6, still unresolved) isn't silently assumed
    away: the caller states explicitly which leaf location each item
    reserves from (`allocations: [{orderItemId, locationId}]`, validated
    to cover exactly the order's items), rather than the backend guessing
    a warehouse.
  - **`POST /orders/:id/cancel` reads the ledger, not a stored column,**
    to know what to release: every `RESERVATION` transaction tagged with
    `order_id = this order` is looked up and matched by a
    `RELEASE_RESERVATION` of the same product/location/quantity. This is
    why `order_items` needs no `location_id` column despite reservation
    being location-specific — `inventory_transactions` is already the
    source of truth for "what's reserved and where" (same principle as
    the ledger being the truth for balances). If the order was never
    reserved, cancel just flips the status.
  - **Verified live end-to-end**: DRAFT→SUBMITTED→PENDING_APPROVAL→
    APPROVED→STOCK_RESERVED with one `order_status_history` row per hop;
    reserving leaves `on_hand` unchanged while `reserved` rises and
    `available` falls by the same amount; the ledger shows a `RESERVATION`
    row with `order_id` set; an illegal transition (`DRAFT→APPROVED`
    direct) is rejected (409); cancelling a `STOCK_RESERVED` order writes
    a matching `RELEASE_RESERVATION` and restores `available`;
    `payment_status` stays `UNPAID` across the whole lifecycle;
    `customers` CRUD works (`customers.create` write, new `customers.view`
    read — not in §F, added because the task asked for "a view
    permission"); a direct `inventory_balances` write is still blocked by
    the Phase 1D trigger; every mutation wrote an `audit_logs` row.
- **Phase 1F — picking, packing, dispatch: completes the order lifecycle.**
  Extends `ORDER_STATUS_TRANSITIONS` in place (not a fork) —
  `STOCK_RESERVED → PICKING → PACKED → READY_FOR_DISPATCH → DISPATCHED
  (or PARTIALLY_FULFILLED) → DELIVERED → COMPLETED`. Picking/packing are
  physical confirmations with **zero ledger effect** — only `dispatch()`
  calls `InventoryService.applyTransaction()`, still the frozen Phase 1D
  engine, untouched.
  - **Deduction point is DISPATCH** (Open Decision 1, resolved). Per item,
    using the exact leaf location it was reserved at (recovered from the
    order's `RESERVATION` ledger rows — same recovery pattern `cancel()`
    already used, now reused by `pick()` and `dispatch()` too, so no
    location is ever client input again after `reserve()`):
    `RELEASE_RESERVATION(fulfilled qty)` then `ISSUE(fulfilled qty)`. Net
    for a fully-fulfilled line: `on_hand` and `reserved` drop by the same
    amount, `available` unchanged — verified live.
  - **Partial fulfilment** (Open Decision 5): if any line's packed qty is
    less than ordered, the order goes `PARTIALLY_FULFILLED` instead of
    `DISPATCHED` — decided by computing the target status from every
    line's `quantityPacked` *before* validating the hop against the map
    and *before* any ledger call, so an order not actually in
    `READY_FOR_DISPATCH` fails with zero side effects regardless of which
    of the two targets it would have picked. For a short line, the
    *unfulfilled remainder* (`ordered − fulfilled`) gets its own
    `RELEASE_RESERVATION` — the full originally-reserved quantity is
    always cleared, but `on_hand` only drops by what actually shipped, so
    the unshipped remainder becomes available again. No backorder is
    auto-created (a human decides whether to re-order) — verified live:
    10 ordered / 8 packed dispatches `PARTIALLY_FULFILLED` with
    `quantity_fulfilled=8`, ledger `RELEASE_RESERVATION(8) + ISSUE(8) +
    RELEASE_RESERVATION(2)`, `on_hand` down 8, `reserved` down the full
    10 (to 0), `available` up by the 2-unit shortfall.
  - **`quantity_picked`/`quantity_packed`** are new `order_items` columns
    (additive — the only schema touch to a Phase 1E table; nothing about
    existing 1E columns or behavior changed). Neither is a ledger event;
    `pack()` validates `packedQty ≤ pickedQty`, `pick()` validates
    `pickedQty ≤ quantityOrdered` (short pick allowed, never more) —
    verified live that over-packing relative to picked is rejected (400).
  - **Cancel, minimally widened.** `ORDER_STATUS_TRANSITIONS` now allows
    `CANCELLED` from `PICKING`/`PACKED`/`READY_FOR_DISPATCH` too (still
    not from `DISPATCHED` onward — physical stock has left). Since
    picking/packing never touch the ledger, the full reserved quantity is
    still sitting in `reserved` at those stages exactly like
    `STOCK_RESERVED` — so `OrdersService.cancel()`'s "was stock reserved"
    check was widened from `status === 'STOCK_RESERVED'` to membership in
    `ORDER_STATUSES_WITH_ACTIVE_RESERVATION`. This is the one line of
    *existing* 1E logic this phase touches, and only because the
    condition it checks (which statuses have live reservations) is
    genuinely different now that PICKING/PACKED/READY_FOR_DISPATCH exist
    — the release logic itself, and every other 1E code path, is
    unchanged. Verified live: cancelling mid-`PICKING` releases the
    reservation correctly; cancelling a `DISPATCHED` order is rejected
    (409) — a return flow (`RETURNED`) is out of scope for 1F.
  - **No new permission keys.** `fulfilment.pick`/`.pack`/`.dispatch` were
    already seeded to WAREHOUSE in Phase 1A's forward-looking catalog
    (§F). `/ready`, `/dispatch`, `/deliver` all use `fulfilment.dispatch`
    per the task; `/complete` names no permission in the task at all — it
    reuses `fulfilment.dispatch` too (documented in the controller), the
    natural continuation of the same fulfilment workflow.
  - Verified live end-to-end: a fully-stocked order runs
    `STOCK_RESERVED→PICKING→PACKED→READY_FOR_DISPATCH→DISPATCHED→
    DELIVERED→COMPLETED` with one `order_status_history` row per hop; an
    illegal hop (`STOCK_RESERVED→DISPATCHED` direct) is rejected (409)
    with a message naming the action actually called, not an internal
    implementation detail; `payment_status` stays `UNPAID` throughout;
    a direct `inventory_balances` write is still blocked by the Phase 1D
    trigger; every mutation (pick/pack/ready/dispatch/deliver/complete)
    wrote an `audit_logs` row.
- **Phase 1G — reports, audit log viewer, dashboard. Completes the Phase 1
  backend.** Strictly read-only: every route is a `GET`, no new tables, no
  writes, no `AuditInterceptor` activity (it only fires on mutating verbs).
  `ReportsService`/`AuditService`/`DashboardService` inject only
  `PrismaService` — no dependency on any 1A–1F service — and every number
  they return comes from reading `inventory_balances`,
  `inventory_transactions`, `orders`/`order_items`, `stock_adjustments`, or
  `audit_logs` directly, the same tables the rest of the system already
  writes. Nothing here recomputes a quantity a second, parallel way.
  - **New permission `reports.view`** (not in §F; the task asked for one),
    granted to ADMIN + MANAGER only — same distribution as the pre-existing
    `audit.view`. No other 1A–1F file changed: `app.module.ts` only grew
    three new module imports, the same way every prior phase registered
    itself.
  - **`GET /reports/low-stock`** sums `inventory_balances.on_hand` across
    every location per product (`groupBy`, not a ledger recomputation) and
    compares against `products.min_stock_level`; returns only products
    actually below threshold, each with a computed `shortfall`.
  - **`GET /reports/inventory-valuation`** sums `on_hand * cost_price` per
    product. `cost_price` is nullable (Phase 1B) — a product with no cost
    is **excluded** from `totalValuation` and reported separately in
    `excludedProducts`/`excludedCount`, never treated as `cost_price = 0`
    (which would silently understate the total instead of flagging the
    gap). Zero-stock products are skipped either way — they contribute
    nothing to a valuation regardless of costing.
  - **`GET /reports/stock-movement`** and the type-fixed
    `/reports/receiving`, `/reports/transfers`, `/reports/adjustments` are
    all filtered reads of `inventory_transactions` (`?productId&
    locationId&type&from&to`), each with a `groupBy`-derived summary —
    nothing beyond what the ledger already holds.
  - **`/reports/adjustments`' best-effort join.** `inventory_transactions`
    has no FK back to `stock_adjustments` — Phase 1D's
    `StockAdjustmentsService.approve()` (frozen, untouched) calls
    `applyTransaction()` and then separately updates the adjustment's
    status, but never persists the resulting transaction id anywhere, and
    this phase can't modify that code to add one. Each `ADJUSTMENT`-type
    ledger row is matched to its likely originating request by
    `(productId, locationId, quantity = delta, reviewedBy = performedBy,
    status = APPROVED)` — exact in the overwhelming common case, falling
    back to the most-recently-reviewed match on a genuine ambiguity (the
    same reviewer approving two identical-quantity requests for the same
    product/location). Documented in code as a known limitation, not
    presented as a guaranteed relational join.
  - **`GET /reports/orders`** derives `count`/`totalValue`/`byStatus`
    entirely from `orders.status` and `orders.total` — never recomputed
    from `order_items.unit_price * quantity`. Called with no filters, it's
    also the exact source `DashboardService` reuses for the pipeline
    snapshot (rather than querying orders a second, parallel way).
  - **`GET /audit-logs`** — a plain paginated, filtered, newest-first read
    of the `audit_logs` rows `AuditInterceptor` already writes on every
    mutating route since Phase 1A. `?userId&entity&entityId&action&from&to`
    plus `page`/`pageSize` (default 20, max 100).
  - **`GET /dashboard`** aggregates the reports above rather than
    reimplementing them: `ordersByStatus` **is**
    `getOrdersReport().byStatus`; `lowStockCount` **is**
    `getLowStock().count`; `today`/`thisWeek` are the same
    `getOrdersReport()` call with a computed `from` date (today = local
    midnight; this week = the preceding Monday). Only
    `pendingAdjustmentsCount` is its own direct `stock_adjustments`
    count — there was no existing report to reuse for it, and adding a
    whole report method for one number seemed like more than the task asked for.
  - Verified live: low-stock returned exactly the one sub-threshold
    product with the correct `shortfall`; stock-movement for a known
    product matched the raw `/inventory/transactions` read row-for-row;
    valuation excluded every null-cost product (including four unrelated
    leftover products from earlier phases' own testing) and its total
    equalled `on_hand * cost_price` for the one costed product only; the
    orders report's `byStatus` breakdown summed to its own overall
    `count`/`totalValue`, and filtering by one status reproduced that
    status's exact row from the unfiltered call; the adjustments report
    correctly resolved requester and approver for an approved adjustment;
    the dashboard's `ordersByStatus` and `pendingAdjustmentsCount` matched
    their sources exactly; audit-log pagination math and every filter
    (entity, action) worked and results were confirmed newest-first; a
    WAREHOUSE user (holds neither `reports.view` nor `audit.view`) got 403
    from every 1G route while MANAGER got 200; zero `audit_logs` rows were
    written by any of this phase's GET requests.

## Database: MySQL / MariaDB (migrated from Postgres)

This project originally targeted Postgres; it now runs on MySQL/MariaDB
(local via XAMPP). Everything above still holds — the migration only
changed *how* it's implemented, not *what* it guarantees. Concretely:

- `datasource provider` is `mysql`; `DATABASE_URL` points at
  `mysql://root:@localhost:3306/distribution_platform` (XAMPP defaults —
  `root`, empty password, port 3306).
- **Requires MySQL 8.0+ or MariaDB 10.2.2+** — recursive CTEs (the
  location subtree query) don't exist before that. Check with
  `SELECT VERSION();` before running migrations on an unfamiliar instance.
- `Json` fields (`audit_logs.old_value`/`new_value`) map to native MySQL
  `JSON` automatically — no schema change needed beyond the provider
  switch. `Decimal`/`@db.Decimal(p,s)` (all money and quantity columns)
  is identical syntax on both providers.
- Prisma's `mode: 'insensitive'` filter option is Postgres-only; removed
  from the product search filter (`ProductsService.findAll`) — MySQL's
  default `utf8mb4_unicode_ci` collation already makes `contains`
  case-insensitive, so behavior is unchanged.
- The `inventory_balances` write-guard trigger (see below) is rebuilt with
  MySQL trigger syntax (`SIGNAL SQLSTATE`, one trigger per event, an
  explicitly-reset session variable) — the guarantee it enforces is
  identical, but the mechanism had to change; see the inventory section
  above for why `SET LOCAL` doesn't translate directly.
- Raw `$queryRaw` results on MySQL don't get Prisma's usual type
  coercion: `locations.is_active` (`TINYINT(1)` under the hood) comes
  back as `0`/`1`, not `true`/`false`. `LocationsService`'s subtree row
  mapper coerces it explicitly so the API response shape is identical to
  every other endpoint regardless of provider.

## Prerequisites

- Node.js 20+
- MySQL 8.0+ or MariaDB 10.2.2+ — XAMPP's bundled MySQL/MariaDB works;
  confirm the version with `SELECT VERSION();` first

## Setup

```bash
npm install
cp .env.example .env
# edit .env if your XAMPP MySQL isn't on the default root/no-password/3306
```

Start XAMPP's MySQL (via the XAMPP Control Panel, or `mysql_start.bat` in
the XAMPP install dir), then create the database if it doesn't exist:

```bash
mysql -u root -e "CREATE DATABASE IF NOT EXISTS distribution_platform CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
```

Apply the schema and seed reference data:

```bash
npx prisma migrate dev
npm run seed
```

The seed creates an admin user from `SEED_ADMIN_EMAIL` / `SEED_ADMIN_PASSWORD`
in `.env` (defaults: `admin@example.com` / `ChangeMe123!`).

## Run

```bash
npm run start:dev
```

- API: http://localhost:3000
- Swagger/OpenAPI docs: http://localhost:3000/docs

## Endpoints (Phase 1A–1G — Phase 1 backend complete)

```
POST   /auth/login
POST   /auth/refresh
POST   /auth/logout

GET    /users/me
GET    /users              (users.manage)
GET    /users/:id          (users.manage)
POST   /users              (users.manage)
PATCH  /users/:id          (users.manage)
DELETE /users/:id          (users.manage — deactivates, does not hard-delete)

GET    /roles              (roles.manage)
GET    /roles/:id          (roles.manage)
POST   /roles              (roles.manage)
PATCH  /roles/:id          (roles.manage)
PUT    /roles/:id/permissions   (roles.manage — replaces the role's permission set)
DELETE /roles/:id          (roles.manage — blocked for system roles or roles still assigned to users)

GET    /permissions        (roles.manage)

GET    /categories                  (catalogue.view — ?parentId=&includeInactive=)
GET    /categories/:id              (catalogue.view)
POST   /categories                  (products.manage)
PATCH  /categories/:id              (products.manage — rejects cyclic parentId with 409)
DELETE /categories/:id              (products.manage — soft-delete, sets is_active=false)

GET    /products                    (catalogue.view — ?categoryId=&status=&includeInactive=&search=)
GET    /products/:id                (catalogue.view)
POST   /products                    (products.manage)
PATCH  /products/:id                (products.manage)
DELETE /products/:id                (products.manage — soft-delete, sets status=INACTIVE)

GET    /products/:productId/images              (catalogue.view)
POST   /products/:productId/images              (products.manage — isPrimary:true unsets any other primary image)
PATCH  /products/:productId/images/:imageId      (products.manage)
DELETE /products/:productId/images/:imageId      (products.manage — hard delete; images aren't historical reference data)

GET    /warehouses                  (warehouse.structure.manage — ?includeInactive=)
GET    /warehouses/:id              (warehouse.structure.manage)
POST   /warehouses                  (warehouse.structure.manage)
PATCH  /warehouses/:id              (warehouse.structure.manage)
DELETE /warehouses/:id              (warehouse.structure.manage — soft-delete, sets is_active=false)

GET    /locations                           (warehouse.structure.manage — ?warehouseId=&parentId=&rootOnly=&includeInactive=)
GET    /locations/:id                       (warehouse.structure.manage)
GET    /locations/:id/children              (warehouse.structure.manage — direct children only, ?includeInactive=)
GET    /locations/:id/subtree               (warehouse.structure.manage — recursive CTE, root + all descendants with depth)
POST   /locations                           (warehouse.structure.manage — needs warehouseId or parentId)
POST   /locations/:id/children              (warehouse.structure.manage — create one child under :id)
POST   /locations/:id/levels                (warehouse.structure.manage — create N sibling children under :id, count is uncapped)
POST   /locations/:id/move                  (warehouse.structure.manage — reposition in the tree; rejects cycles (409) and cross-warehouse moves (400))
PATCH  /locations/:id                       (warehouse.structure.manage — field edits only, not parentId)
DELETE /locations/:id                       (warehouse.structure.manage — soft-delete, sets is_active=false)

GET    /inventory/balances                  (inventory.view — ?productId=&locationId=&warehouseId=; each row includes computed available)
GET    /inventory/transactions              (inventory.view — ?productId=&locationId=&type=&from=&to=)

POST   /inventory/receiving                 (inventory.receive — RECEIVE at toLocationId, must be a leaf)
POST   /inventory/transfers                 (inventory.transfer — one TRANSFER, from/to must both be leaves)

GET    /inventory/adjustments               (inventory.view — ?status=)
POST   /inventory/adjustments               (inventory.adjust.request — creates PENDING, moves no stock, reason mandatory)
POST   /inventory/adjustments/:id/approve   (inventory.adjust.approve — moves stock; 403 if reviewer === requester; 409 if not PENDING)
POST   /inventory/adjustments/:id/reject    (inventory.adjust.approve — reviewNote mandatory; moves no stock; 409 if not PENDING)

GET    /inventory/counts                    (inventory.count — ?status=&locationId=)
GET    /inventory/counts/:id                (inventory.count — includes items)
POST   /inventory/counts                    (inventory.count — snapshots expected_qty at a leaf location; ?productIds or all products with a balance there)
PATCH  /inventory/counts/:id                (inventory.count — submit counted quantities for exactly the snapshotted set; nonzero differences become PENDING stock_adjustments; 409 if not OPEN)

GET    /customers                           (customers.view — ?includeInactive=&search=)
GET    /customers/:id                       (customers.view)
POST   /customers                           (customers.create)
PATCH  /customers/:id                       (customers.create)
DELETE /customers/:id                       (customers.create — soft-delete, sets status=INACTIVE)

GET    /orders                              (orders.view_own — scoped to own unless caller also has orders.view_team; ?status=&customerId=)
GET    /orders/:id                          (orders.view_own — same scoping; 404, not 403, outside scope)
POST   /orders                              (orders.create — creates DRAFT with items; unit_price snapshotted server-side; payment_status=UNPAID)
PATCH  /orders/:id                          (orders.edit_own_draft — DRAFT-only, owner-only; items replace the full set)
POST   /orders/:id/submit                   (orders.submit — DRAFT -> SUBMITTED -> PENDING_APPROVAL, two history rows)
POST   /orders/:id/approve                  (orders.approve — PENDING_APPROVAL -> APPROVED)
POST   /orders/:id/reject                   (orders.reject — -> REJECTED, note mandatory)
POST   /orders/:id/reserve                  (orders.approve — APPROVED -> STOCK_RESERVED; all-or-nothing RESERVATION per item; 409 on any shortfall)
POST   /orders/:id/cancel                   (orders.approve — -> CANCELLED from any state up to READY_FOR_DISPATCH; releases reservations if any are active; rejected once DISPATCHED)

POST   /orders/:id/pick                     (fulfilment.pick — STOCK_RESERVED -> PICKING; records picked qty per line, <= ordered, no ledger effect)
POST   /orders/:id/pack                     (fulfilment.pack — PICKING -> PACKED; records packed qty per line, <= picked, no ledger effect)
POST   /orders/:id/ready                    (fulfilment.dispatch — PACKED -> READY_FOR_DISPATCH)
POST   /orders/:id/dispatch                 (fulfilment.dispatch — READY_FOR_DISPATCH -> DISPATCHED or PARTIALLY_FULFILLED; deduction point: RELEASE_RESERVATION + ISSUE per line, plus a remainder RELEASE_RESERVATION on a short line)
POST   /orders/:id/deliver                  (fulfilment.dispatch — DISPATCHED or PARTIALLY_FULFILLED -> DELIVERED; no ledger effect)
POST   /orders/:id/complete                 (fulfilment.dispatch — DELIVERED -> COMPLETED; no permission was named in the task for this one, reuses fulfilment.dispatch)

GET    /reports/low-stock                   (reports.view — products where summed on_hand < min_stock_level, with shortfall)
GET    /reports/stock-movement              (reports.view — ?productId&locationId&type&from&to; grouped summary + filtered ledger rows)
GET    /reports/inventory-valuation         (reports.view — sum(on_hand*cost_price); excludes and separately lists null-cost products)
GET    /reports/orders                      (reports.view — ?status&from&to&customerId; count/totalValue/byStatus, derived from orders.status/total)
GET    /reports/receiving                   (reports.view — RECEIVE-type ledger, ?productId&locationId&from&to)
GET    /reports/transfers                   (reports.view — TRANSFER-type ledger, ?productId&locationId&from&to)
GET    /reports/adjustments                 (reports.view — ADJUSTMENT-type ledger, ?productId&locationId&from&to; each row best-effort joined to its stock_adjustments request)

GET    /audit-logs                          (audit.view — ?userId&entity&entityId&action&from&to; paginated ?page&pageSize, newest first)

GET    /dashboard                           (reports.view — ordersByStatus, lowStockCount, pendingAdjustmentsCount, today/thisWeek order count+value)
```

Every route except `/auth/*` and `/users/me` requires a Bearer access token
(`AuthGuard`) and, where noted, the listed permission key (`PermissionGuard`).

## Auth flow

1. `POST /auth/login` → `{ accessToken, refreshToken, user }`. The access
   token is a 15-minute JWT signed with `JWT_ACCESS_SECRET`; the refresh
   token is a longer-lived JWT (default 7d) signed with a *different*
   secret (`JWT_REFRESH_SECRET`) whose id (`jti`) matches a
   `refresh_tokens` row. Only an argon2 hash of the refresh token is stored
   — the raw token is never persisted.
2. `POST /auth/refresh` with `{ refreshToken }` verifies the JWT, checks the
   matching DB row (not revoked, not expired, hash matches), then **rotates**:
   the old row is marked revoked and a brand new access + refresh token pair
   is issued. Reusing an old refresh token after rotation fails.
3. `POST /auth/logout` with `{ refreshToken }` revokes that refresh token.
   Idempotent — logging out twice, or with an already-invalid token, still
   returns `{ success: true }`.

## Scripts

```bash
npm run start:dev       # watch mode
npm run build            # compile to dist/
npm run prisma:migrate    # create + apply a dev migration
npm run prisma:deploy     # apply pending migrations (CI/prod)
npm run prisma:studio     # Prisma Studio GUI
npm run seed               # run prisma/seed.ts
```

## Project layout

```
prisma/
  schema.prisma     users, roles, permissions, role_permissions, user_roles,
                     refresh_tokens, audit_logs, categories, products,
                     product_images, warehouses, locations,
                     inventory_balances, inventory_transactions,
                     stock_adjustments, stock_counts, stock_count_items,
                     customers, orders, order_items (+ quantity_picked/
                     quantity_packed, added in 1F), order_status_history
  migrations/*/migration.sql   the init_mysql migration hand-adds the
                     CHECK(>= 0) constraints and the three write-guard
                     triggers — things Prisma's schema DSL can't express
                     natively. Every migration since (phase_1d_part2,
                     1e, 1f) is plain CREATE TABLE/FK/ALTER — no
                     hand-editing needed.
  seed.ts             also deletes any `permissions` row whose key is no
                     longer in the catalog (e.g. the retired flat
                     inventory.adjust, replaced by .request/.approve)
src/
  common/
    prisma/          PrismaService/PrismaModule (global)
    guards/          AuthGuard, PermissionGuard
    decorators/       @Public(), @RequirePermissions(), @CurrentUser()
    interceptors/     AuditInterceptor (global, APP_INTERCEPTOR)
    filters/           AllExceptionsFilter (global)
    utils/, types/
  auth/               /auth/login, /auth/refresh, /auth/logout
  users/              /users CRUD
  roles/              /roles CRUD + /roles/:id/permissions
  permissions/        /permissions list + the seeded permission catalog
  categories/         /categories CRUD (self-referencing tree, cycle-checked)
  products/           /products CRUD (imports CategoriesModule to validate categoryId)
  product-images/     /products/:productId/images CRUD (imports ProductsModule)
  warehouses/         /warehouses CRUD
  locations/          /locations CRUD + children/subtree/move/levels
                       (imports WarehousesModule; subtree via $queryRaw WITH RECURSIVE)
  inventory/          InventoryService.applyTransaction() (the sole balance
                       writer) + read-only /inventory/balances,
                       /inventory/transactions (imports ProductsModule,
                       LocationsModule); inventory-transaction-effects.ts
                       holds the type -> bucket-delta config
  receiving/          /inventory/receiving (imports InventoryModule, LocationsModule)
  transfers/           /inventory/transfers (imports InventoryModule, LocationsModule)
  stock-adjustments/   /inventory/adjustments CRUD + approve/reject — two-step
                       approval (imports ProductsModule, LocationsModule,
                       InventoryModule); exports StockAdjustmentsService so
                       stock-counts can create adjustments the same way
  stock-counts/        /inventory/counts start/submit (imports ProductsModule,
                       LocationsModule, StockAdjustmentsModule)
  customers/            /customers CRUD (soft-delete via status)
  orders/               /orders — full lifecycle: DRAFT through
                       COMPLETED, plus REJECTED/CANCELLED/
                       PARTIALLY_FULFILLED. order-status-transitions.ts
                       holds the whole state-machine config (1E built
                       DRAFT..STOCK_RESERVED; 1F extended it in place with
                       picking/packing/dispatch); imports CustomersModule,
                       ProductsModule, LocationsModule, InventoryModule —
                       calls applyTransaction() for RESERVATION/
                       RELEASE_RESERVATION/ISSUE, never writes
                       inventory_balances itself
  reports/              /reports/* — read-only aggregation over
                       inventory_balances, inventory_transactions,
                       orders/order_items, stock_adjustments. Injects only
                       PrismaService — no dependency on any 1A-1F service.
                       Exports ReportsService for DashboardModule to reuse.
  audit/                /audit-logs — paginated, filtered read of audit_logs
  dashboard/            /dashboard (imports ReportsModule; reuses its
                       methods rather than re-querying)
  app.module.ts
  main.ts
```
