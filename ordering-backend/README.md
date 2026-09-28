# ordering-backend

The Back-Office / Ordering System API (customers, orders, fulfilment, reports, users/roles) — plain
JavaScript on **Node.js + Express**, **no ORM**: every query is parameterised SQL through `mysql2`.
It replaces the NestJS + Prisma `/backend` with the **same routes, request/response shapes,
permissions and `distribution_platform` schema**; `/ordering-frontend` talks only to it.

Like every part of this platform it follows CLAUDE.md: permissions not roles, the order state machine
in config (`src/modules/order-status-transitions.js`), payment status independent of order status,
backend-enforced security, an audit row on every successful mutation, soft-deleted reference data.
It owns **no inventory**: stock is reserved, released and issued through the warehouse system's
API-key-protected external API (`src/core/warehouse-api.js` — the only code that calls it).

## Run it

```bash
cp .env.example .env    # DATABASE_URL, JWT secrets, WAREHOUSE_API_URL + WAREHOUSE_API_KEY
npm install
mysql -u root -e "CREATE DATABASE distribution_platform CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
mysql -u root distribution_platform < db/schema.sql
npm run seed            # permissions, roles, admin user
npm start               # or: npm run dev  (node --watch)
```

Port 3300 by default. The warehouse API key is issued in the warehouse app (Settings → API keys) with
the scopes `catalogue:read`, `stock:read`, `stock:reserve`, `stock:issue`, `locations:read`.

## Schema changes (no migration tool)

`db/schema.sql` is the whole schema. To change a live database, write the `ALTER`, run it once on each
database, and make the same edit in `schema.sql` in the same commit.

## Layout

```
app.js                 cPanel/Passenger entry (loads .env, starts src/server)
src/app.js             buildApp(): middleware, services, route table
src/config.js          env -> config
src/core/              db pool, table metadata + SQL helpers, auth guards, audit middleware,
                       error handling + route wrapper, warehouse API client
src/modules/           auth, users, roles (+permissions), audit, customers, orders (+catalogue and
                       warehouse-location relays), reports (+dashboard)
src/catalog/           the permission catalog and default role grants
db/                    schema.sql, seed.js
test/                  integration suite (fake warehouse, throwaway DB) + parity.js
```

## Differences from the NestJS `/backend`

* An insufficient-stock reserve (409) keeps the same message **and** now carries structured
  `shortLines` in the body, so clients no longer need to parse the text.
* A reject note of only whitespace is refused (400) — the UI already trimmed it; now the API does too.
* Warehouse calls time out after `WAREHOUSE_API_TIMEOUT_MS` (20 s) as a clean 503 "safe to retry".
* No Swagger UI at `/docs`. `GET /health` is new.

## Testing

```bash
mysql -u root -e "CREATE DATABASE distribution_platform_test CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
mysql -u root distribution_platform_test < db/schema.sql
DATABASE_URL=mysql://root:@localhost:3306/distribution_platform_test SEED_ADMIN_EMAIL=admin@test.local SEED_ADMIN_PASSWORD='TestPass123!' npm run seed
npm test
```

The suite runs the whole order lifecycle against an in-process fake warehouse (no real stock is
touched). `test/parity.js` replays every read endpoint against the legacy `/backend` and this port on
the same database and diffs the results (33/33 identical at the switch).

## Deploying on cPanel (Phusion Passenger)

Application startup file: `app.js`. No build step. `npm ci --omit=dev` on the server (`argon2` is
native — never upload a Windows-built `node_modules`), set the env vars, restart. Set
`API_BASE_PATH` if the app URL has a path.
