'use strict';

const { MemoryStore } = require('./memory-store');

/**
 * CacheStore contract (implement this to plug in Redis or anything else):
 *   get(key)                              -> Promise<value | undefined>
 *   set(key, value, { ttlMs, tags })      -> Promise<void>
 *   del(key)                              -> Promise<void>
 *   invalidateTags(tags: string[])        -> Promise<void>   (drop every key stored with any of the tags)
 *   clear()                               -> Promise<void>
 * A Redis implementation would JSON-serialise values and keep one SET per tag.
 *
 * The Cache class adds what a raw store does not give you:
 *   - single-flight loading: N concurrent misses for a key run the loader once
 *   - invalidation-safe loads: a value loaded while its tag was being invalidated
 *     is returned to the caller but never stored (no stale write-after-invalidate)
 *   - hit/miss counters
 *   - a kill switch (CACHE_ENABLED=false) that turns every wrap() into a plain load
 *
 * What must NEVER be cached: anything a write decision reads (stock availability,
 * reserve/release/issue, ledger balances inside a transaction). Reads that only
 * render a screen may be cached, provided every write that changes them
 * invalidates the matching tag.
 */
class Cache {
  constructor(store, { enabled = true } = {}) {
    this.store = store;
    this.enabled = enabled;
    this.inflight = new Map();
    this.tagVersions = new Map();
    this.stats = { hits: 0, misses: 0, coalesced: 0, invalidations: 0 };
  }

  /**
   * Returns the cached value for `key`, or runs `loader` once and caches its result.
   * opts: { ttlMs: number, tags?: string[] }
   */
  async wrap(key, opts, loader) {
    if (!this.enabled) return loader();

    const cached = await this.store.get(key);
    if (cached !== undefined) {
      this.stats.hits++;
      return cached;
    }

    const pending = this.inflight.get(key);
    if (pending) {
      this.stats.coalesced++;
      return pending;
    }

    this.stats.misses++;
    const tags = opts.tags ?? [];
    const versionsBefore = tags.map((t) => this.tagVersions.get(t) ?? 0);

    const promise = (async () => {
      try {
        const value = await loader();
        const invalidatedMeanwhile = tags.some((t, i) => (this.tagVersions.get(t) ?? 0) !== versionsBefore[i]);
        if (value !== undefined && !invalidatedMeanwhile) {
          await this.store.set(key, value, { ttlMs: opts.ttlMs, tags });
        }
        return value;
      } finally {
        this.inflight.delete(key);
      }
    })();

    this.inflight.set(key, promise);
    return promise;
  }

  async get(key) {
    return this.enabled ? this.store.get(key) : undefined;
  }

  async set(key, value, opts) {
    if (this.enabled) await this.store.set(key, value, opts);
  }

  async del(key) {
    await this.store.del(key);
  }

  /** Drop everything stored under any of these tags. Call AFTER the write commits. */
  async invalidate(...tags) {
    const flat = tags.flat();
    for (const tag of flat) this.tagVersions.set(tag, (this.tagVersions.get(tag) ?? 0) + 1);
    this.stats.invalidations += flat.length;
    await this.store.invalidateTags(flat);
  }

  snapshot() {
    const { hits, misses } = this.stats;
    const total = hits + misses;
    return { ...this.stats, hitRate: total ? Number((hits / total).toFixed(3)) : 0, size: this.store.size?.() };
  }
}

function createCache(cacheConfig) {
  if (cacheConfig.store !== 'memory') {
    throw new Error(
      `Unknown CACHE_STORE "${cacheConfig.store}". Only "memory" is built in; implement the CacheStore contract in core/cache/cache.js to add another.`,
    );
  }
  const store = new MemoryStore({ maxEntries: cacheConfig.maxEntries, defaultTtlMs: 60_000 });
  return new Cache(store, { enabled: cacheConfig.enabled });
}

/** Central list of cache tags, so writers and readers cannot drift apart. */
const TAGS = {
  PERMISSIONS: 'permissions',
  API_KEYS: 'api-keys',
  SCOPES: 'workstream-scopes', // which workstreams a user is assigned to manage
  CATALOGUE: 'catalogue', // products, categories, workstreams, attribute types, images
  STRUCTURE: 'structure', // warehouses + locations tree
  STOCK: 'stock', // anything derived from the inventory ledger
  SETTINGS: 'settings', // admin-editable app settings (email/SMS delivery)
  SALES: 'sales', // sale campaigns + which products are currently on sale
};

module.exports = { Cache, createCache, TAGS };
