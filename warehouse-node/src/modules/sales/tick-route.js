'use strict';

const { notFound } = require('../../core/errors');

/**
 * `POST /internal/sales-tick` — the cPanel Cron Job hits this once a minute (see README.md's
 * deploy section) so `SalesService.tick()` runs inside the LIVE server process (needed to
 * invalidate its in-memory cache the instant a campaign starts/ends — a standalone script talking
 * straight to the DB could not do that). Not part of the authenticated app API (no user session)
 * and not part of the external partner API (`/api/v1`, API-key scopes) — its own tiny trust
 * boundary: one shared secret, header `X-Cron-Secret`, checked against `config.cronSecret`.
 * `cronSecret` unset means this route always 404s — never silently open.
 */
function salesTickRoutes(app) {
  const { config, services } = app;

  app.post('/sales-tick', {}, async (request) => {
    if (!config.cronSecret || request.headers['x-cron-secret'] !== config.cronSecret) {
      throw notFound('Not found');
    }
    return services.sales.tick();
  });
}

module.exports = salesTickRoutes;
