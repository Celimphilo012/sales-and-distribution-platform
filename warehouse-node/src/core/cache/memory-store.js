'use strict';

const { LRUCache } = require('lru-cache');

/**
 * In-process LRU store. Implements the CacheStore contract (see cache.js):
 *   get(key) / set(key, value, { ttlMs, tags }) / del(key) / invalidateTags(tags) / clear()
 * Every method is async so a Redis store can be swapped in without touching callers.
 *
 * Values are stored by reference (no clone) — cached values must be treated as
 * immutable by whoever reads them.
 */
class MemoryStore {
  constructor({ maxEntries, defaultTtlMs }) {
    this.tagIndex = new Map(); // tag -> Set<key>
    this.keyTags = new Map(); // key -> string[]
    this.lru = new LRUCache({
      max: maxEntries,
      ttl: defaultTtlMs,
      ttlAutopurge: false,
      // Keep the tag index in step with eviction/expiry so it cannot grow unbounded.
      dispose: (_value, key) => this.unindex(key),
    });
  }

  async get(key) {
    return this.lru.get(key);
  }

  async set(key, value, { ttlMs, tags } = {}) {
    this.unindex(key);
    this.lru.set(key, value, ttlMs ? { ttl: ttlMs } : undefined);
    if (tags && tags.length) {
      this.keyTags.set(key, tags);
      for (const tag of tags) {
        let keys = this.tagIndex.get(tag);
        if (!keys) this.tagIndex.set(tag, (keys = new Set()));
        keys.add(key);
      }
    }
  }

  async del(key) {
    this.lru.delete(key);
  }

  async invalidateTags(tags) {
    for (const tag of tags) {
      const keys = this.tagIndex.get(tag);
      if (!keys) continue;
      for (const key of [...keys]) this.lru.delete(key); // dispose() cleans the index
      this.tagIndex.delete(tag);
    }
  }

  async clear() {
    this.lru.clear();
    this.tagIndex.clear();
    this.keyTags.clear();
  }

  size() {
    return this.lru.size;
  }

  unindex(key) {
    const tags = this.keyTags.get(key);
    if (!tags) return;
    for (const tag of tags) {
      const keys = this.tagIndex.get(tag);
      if (keys) {
        keys.delete(key);
        if (keys.size === 0) this.tagIndex.delete(tag);
      }
    }
    this.keyTags.delete(key);
  }
}

module.exports = { MemoryStore };
