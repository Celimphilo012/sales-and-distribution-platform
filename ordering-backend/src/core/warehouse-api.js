'use strict';

const { HttpError, notFound } = require('./errors');

const badGateway = (message) => new HttpError(502, 'Bad Gateway', message);
const serviceUnavailable = (message) => new HttpError(503, 'Service Unavailable', message);

/**
 * The SOLE path from this app to the warehouse (ARCHITECTURE.md §A2 — this app is a CLIENT of the
 * warehouse's API-key-protected external API, never a peer with DB access; no other file should
 * call the warehouse). Every request carries X-API-Key and the base URL from env.
 *
 * Two kinds of failure a caller must NOT conflate:
 *   - network/HTTP-level: unreachable (503) or a non-2xx answer (502, carrying the warehouse's own
 *     reason, e.g. "Invalid or inactive API key"). This client THROWS for these.
 *   - business outcomes the warehouse reports as HTTP 200 with a discriminator (insufficient stock,
 *     already released/issued). NEVER thrown — returned as-is; callers branch on the discriminator.
 *
 * Decimal fields come back as JSON strings — callers Number() them.
 */
function createWarehouseApi({ config }) {
  const { url: baseUrl, key: apiKey, timeoutMs } = config.warehouseApi;

  async function request(method, path, body, query) {
    const url = new URL(path, baseUrl);
    for (const [k, v] of Object.entries(query ?? {})) {
      if (v !== undefined && v !== null) url.searchParams.set(k, String(v));
    }

    let response;
    try {
      response = await fetch(url, {
        method,
        headers: { 'X-API-Key': apiKey, ...(body ? { 'Content-Type': 'application/json' } : {}) },
        body: body ? JSON.stringify(body) : undefined,
        signal: AbortSignal.timeout(timeoutMs),
      });
    } catch (error) {
      // Never reached the warehouse (DNS, connection refused, timeout): a retry is always safe.
      throw serviceUnavailable(
        `Warehouse API is unreachable at ${baseUrl} (${error.cause?.message ?? error.message}). This action is safe to retry.`,
      );
    }

    const payload = await response.json().catch(() => undefined);
    if (!response.ok) {
      const reason = (payload && (payload.message ?? payload.error)) ?? response.statusText;
      throw badGateway(
        `Warehouse API request failed (${response.status} ${response.statusText}): ${Array.isArray(reason) ? reason.join('; ') : reason}`,
      );
    }
    return payload;
  }

  const getCatalogue = (query = {}) => request('GET', '/api/v1/catalogue', undefined, query);

  /**
   * The external catalogue API has no by-id read: fetch the catalogue including inactive products
   * (so "inactive" and "doesn't exist" can be told apart) and find it here.
   */
  async function getProduct(productId) {
    const { products } = await getCatalogue({ includeInactive: true });
    const product = products.find((p) => p.id === productId);
    if (!product) throw notFound(`Product ${productId} not found in the warehouse catalogue`);
    return product;
  }

  /** Active + scheduled sale campaigns (name, products, discount/eligibility terms) — for the local
   * eligibility-management screen. Not per-product (that's `sale` on each `getCatalogue()` product). */
  const getSales = () => request('GET', '/api/v1/sales');

  return {
    getCatalogue,
    getProduct,
    getSales,
    getLocations: () => request('GET', '/api/v1/locations'),
    checkAvailability: (items) => request('POST', '/api/v1/stock/availability', { items }),
    /** Per product: active locations with available stock, each with its warehouse and stock age (FIFO). */
    allocationOptions: (productIds) => request('POST', '/api/v1/stock/allocation-options', { productIds }),
    /** `label` is human text the warehouse shows its packers (e.g. "ORD-0012 · Customer name"). */
    reserve: (reference, lines, label) => request('POST', '/api/v1/stock/reserve', { reference, label, lines }),
    release: (reference) => request('POST', '/api/v1/stock/release', { reference }),
    issue: (reference, lines) => request('POST', '/api/v1/stock/issue', { reference, lines }),
  };
}

module.exports = { createWarehouseApi };
