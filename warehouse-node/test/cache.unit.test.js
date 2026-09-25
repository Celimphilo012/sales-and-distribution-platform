'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { Cache } = require('../src/core/cache/cache');
const { MemoryStore } = require('../src/core/cache/memory-store');

const newCache = (opts) => new Cache(new MemoryStore({ maxEntries: 100, defaultTtlMs: 60_000 }), opts);
const tick = (ms = 5) => new Promise((resolve) => setTimeout(resolve, ms));

test('wrap() loads once, then serves from cache', async () => {
  const cache = newCache();
  let loads = 0;
  const loader = async () => ++loads;

  assert.equal(await cache.wrap('k', { ttlMs: 1000 }, loader), 1);
  assert.equal(await cache.wrap('k', { ttlMs: 1000 }, loader), 1);
  assert.equal(loads, 1);
  assert.deepEqual([cache.stats.hits, cache.stats.misses], [1, 1]);
});

test('concurrent misses run the loader once (single-flight)', async () => {
  const cache = newCache();
  let loads = 0;
  const loader = async () => {
    loads++;
    await tick(20);
    return 'value';
  };

  const results = await Promise.all(Array.from({ length: 10 }, () => cache.wrap('k', { ttlMs: 1000 }, loader)));
  assert.equal(loads, 1);
  assert.deepEqual(new Set(results), new Set(['value']));
  assert.equal(cache.stats.coalesced, 9);
});

test('invalidate(tag) drops every key stored under that tag, and only those', async () => {
  const cache = newCache();
  await cache.wrap('a', { ttlMs: 1000, tags: ['stock'] }, async () => 'a');
  await cache.wrap('b', { ttlMs: 1000, tags: ['stock', 'catalogue'] }, async () => 'b');
  await cache.wrap('c', { ttlMs: 1000, tags: ['catalogue'] }, async () => 'c');

  await cache.invalidate('stock');

  assert.equal(await cache.get('a'), undefined);
  assert.equal(await cache.get('b'), undefined);
  assert.equal(await cache.get('c'), 'c');
});

test('a value loaded while its tag was invalidated is returned but never stored (no stale write-after-invalidate)', async () => {
  const cache = newCache();
  let release;
  const gate = new Promise((resolve) => (release = resolve));

  const pending = cache.wrap('k', { ttlMs: 1000, tags: ['stock'] }, async () => {
    await gate; // the "read" is in flight...
    return 'stale';
  });
  await tick();
  await cache.invalidate('stock'); // ...a write commits and invalidates...
  release();

  assert.equal(await pending, 'stale'); // the in-flight caller still gets its answer
  assert.equal(await cache.get('k'), undefined); // but it must not be cached
  assert.equal(await cache.wrap('k', { ttlMs: 1000, tags: ['stock'] }, async () => 'fresh'), 'fresh');
});

test('entries expire after their TTL', async () => {
  const cache = newCache();
  let loads = 0;
  await cache.wrap('k', { ttlMs: 20 }, async () => ++loads);
  await tick(40);
  await cache.wrap('k', { ttlMs: 20 }, async () => ++loads);
  assert.equal(loads, 2);
});

test('a loader that throws is not cached and does not poison later calls', async () => {
  const cache = newCache();
  await assert.rejects(cache.wrap('k', { ttlMs: 1000 }, async () => Promise.reject(new Error('boom'))), /boom/);
  assert.equal(await cache.wrap('k', { ttlMs: 1000 }, async () => 'ok'), 'ok');
});

test('undefined results are not cached (used for "unknown API key")', async () => {
  const cache = newCache();
  let loads = 0;
  await cache.wrap('k', { ttlMs: 1000 }, async () => (loads++, undefined));
  await cache.wrap('k', { ttlMs: 1000 }, async () => (loads++, undefined));
  assert.equal(loads, 2);
});

test('LRU eviction keeps the tag index consistent (no leak, no stale invalidation target)', async () => {
  const store = new MemoryStore({ maxEntries: 2, defaultTtlMs: 60_000 });
  const cache = new Cache(store);
  await cache.wrap('a', { ttlMs: 1000, tags: ['t'] }, async () => 1);
  await cache.wrap('b', { ttlMs: 1000, tags: ['t'] }, async () => 2);
  await cache.wrap('c', { ttlMs: 1000, tags: ['t'] }, async () => 3); // evicts 'a'

  assert.equal(store.tagIndex.get('t').size, 2);
  await cache.invalidate('t');
  assert.equal(store.size(), 0);
  assert.equal(store.tagIndex.size, 0);
});

test('CACHE_ENABLED=false turns wrap() into a plain load', async () => {
  const cache = newCache({ enabled: false });
  let loads = 0;
  await cache.wrap('k', { ttlMs: 1000 }, async () => ++loads);
  await cache.wrap('k', { ttlMs: 1000 }, async () => ++loads);
  assert.equal(loads, 2);
});
