# warehouse-node

Plain-JavaScript (Fastify + Prisma) port of the `/warehouse` NestJS API. It is a **drop-in
replacement**: same routes, same request/response shapes, same permissions, same `warehouse_db`
schema — both Flutter apps and the ordering back-office work against it unchanged. The original
`/warehouse` is untouched and still works; run either one (never both against one production
database expecting separate caches — see *Caching → multiple processes*).

Everything CLAUDE.md requires still holds: permissions not roles, the inventory ledger written only via
`InventoryService.applyTransaction()` (with the DB trigger as backstop), location-aware buckets,
unlimited-depth location tree, state in config, backend-enforced security, an audit row on every
successful mutation, soft-deleted reference data.

## Run it

```bash
cp .env.example .env          # set DATABASE_URL, JWT secrets, CORS_ORIGINS
npm install
npx prisma generate
npx prisma migrate deploy     # same migrations as /warehouse
npm run seed                  # permissions, roles, admin user, system API user, back-office API key
npm start                     # or: npm run dev  (node --watch)
```

Default port is 3200 so it can run beside the original on 3100. Point a frontend/back-office at it by
changing the base URL / `WAREHOUSE_API_URL`; nothing else changes.

## Layout

```
app.js                    cPanel/Passenger entry (loads .env, requires src/server)
src/server.js             listen + graceful shutdown
src/app.js                buildApp(): plugins, hooks, route table  (tests call this directly)
src/container.js          builds every service once, in dependency order
src/config.js             env -> config
src/core/                 auth guards, audit hook, error handling, validation helpers, uploads, cache
src/modules/<name>/       service.js (business logic) + routes.js (HTTP + JSON-Schema validation)
src/catalog/              permission + attribute-type seed catalogs
prisma/                   schema, migrations, seed.js, seed-inventory-demo.js
test/                     unit + integration tests, plus parity.js and bench.js
```

Cross-module calls go through services (rule 9). `routes.js` files declare their guards with
`onRequest: [authenticate, requirePermissions('key')]` — guards run **before** body validation, so an
unauthenticated caller gets 401, never a 400 that leaks the schema.

## Caching

`src/core/cache/` — an in-memory LRU behind a small async `CacheStore` contract
(`get/set/del/invalidateTags/clear`). Swapping in Redis later means implementing that contract in one
file and setting `CACHE_STORE`; no caller changes.

* **Tag-based invalidation.** Every cached value is stored with tags (`stock`, `catalogue`,
  `structure`, `permissions`, `api-keys`, `workstream-scopes`). A write invalidates its tags *after it
  commits*. Reads therefore never serve stale data in the process that made the write.
* **Single-flight.** N concurrent misses for a key run the loader once.
* **No stale write-after-invalidate.** A value that finished loading while its tag was being
  invalidated is returned to its caller but not stored.
* **Kill switch.** `CACHE_ENABLED=false` makes every `wrap()` a plain database read.

What is cached, and what invalidates it:

| Cached | Key tags | Invalidated by |
|---|---|---|
| User's effective permission keys | `permissions` | any role / role-permission / user change |
| Verified API key (by SHA-256 of the key) | `api-keys` | create / revoke |
| Workstream scope of a user | `workstream-scopes` | assign / unassign |
| Warehouses, locations, subtrees | `structure` | any warehouse / location write |
| Workstreams, categories, attribute types | `catalogue` | their own writes |
| Product lists and single products (with `totalOnHand`) | `catalogue`, `stock` | product/image/category writes **and every ledger write** |
| Reports and the dashboard | `stock`, `catalogue`, `structure` | any of the above |
| `/api/v1/catalogue` (external) | via the product/category caches | same |

**Never cached** (correctness beats speed): stock availability, reserve / release / issue, the leaf
check, balances and transactions lists, anything read inside a write, audit logs, `getExisting()`
used for audit old-values. Free-text product search is not cached (unbounded key space).

**Multiple processes.** Invalidation is per process. If you run more than one process against the same
database (cluster/PM2), a change made in process A is seen by B only after the relevant TTL
(`CACHE_*_TTL_MS`). Passenger on cPanel normally runs one process. For strict cross-process
invalidation, implement the Redis store.

## Other optimisations vs the original

* API-key auth: the original verified the key against **every** active key's argon2 hash on **every**
  request. Argon2 stays as the at-rest format; verification now runs once per key per TTL, and
  `last_used_at` is written at most once a minute per key.
* `applyTransaction` and reservation lines use a cheap `assertExists` instead of loading the whole
  product (with its stock aggregate) just to prove it exists; stock counts check all products in one query.
* Audit rows are written in `onResponse`, after the client already has its answer.
* Uploaded images are served with `ETag` + `Cache-Control: private, no-cache`, so revalidation is a
  cheap 304.
* gzip via `@fastify/compress` (large lists compress ~10x), and ETags on JSON.
* Report queries got a deterministic tiebreaker (`ORDER BY … , sku`); the original's order for ties was
  arbitrary.

## Deliberate differences from `/warehouse`

* Validation messages are class-validator-style (`property x should not exist`,
  `email must be a valid email`) but not word-for-word identical for every rule.
  Status codes and the error body shape (`statusCode, error, message, path, timestamp`) are identical.
* A missing upload file is a clean 400 (the original threw a 500).
* Multipart `isPrimary=false` is parsed as false (the original's `Boolean("false")` made it true).
* No Swagger UI at `/docs` (the original had one). It would add several MB of `node_modules` and file
  count, which matters on quota-limited shared hosting; route schemas are already JSON-Schema, so
  `@fastify/swagger` can be added later if wanted.
* `GET /health` (public, returns `{"status":"ok"}`) is new.

## Testing

```bash
# one-time: a throwaway database (the harness refuses any name that does not end in _test)
mysql -u root -e "CREATE DATABASE warehouse_db_test"
DATABASE_URL=mysql://root:@localhost:3306/warehouse_db_test npx prisma migrate deploy
DATABASE_URL=mysql://root:@localhost:3306/warehouse_db_test SEED_ADMIN_EMAIL=admin@test.local SEED_ADMIN_PASSWORD='TestPass123!' node prisma/seed.js

npm test                      # cache unit tests + full API integration suite
```

`test/parity.js` replays every read endpoint (and the error shapes) against the original API and this
port on the same database and diffs the results; `test/bench.js` compares throughput.

## Deploying on cPanel (Phusion Passenger)

Application startup file: `app.js`. No build step — it is plain JavaScript.

```bash
source /home/<user>/nodevenv/<app-root>/<node-version>/bin/activate   # cPanel shows this line
npm ci --omit=dev
npx prisma generate
npx prisma migrate deploy
```

Set the environment variables in cPanel's Node.js app page (or a `.env` in the app root). If the app
URL has a path (e.g. `/api`), set `API_BASE_PATH=api`. Then Restart.

`argon2` and Prisma's query engine are native: install on the server (never upload `node_modules`
built on Windows). `prisma` is a dependency (not a devDependency) so `migrate deploy` works after
`--omit=dev`.
