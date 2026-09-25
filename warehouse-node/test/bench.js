'use strict';

/**
 * Tiny load generator for comparing the original API with this port on READ endpoints.
 *
 *   OLD_URL=http://localhost:3100 NEW_URL=http://localhost:3200 \
 *   BENCH_EMAIL=... BENCH_PASSWORD=... [BENCH_API_KEY=whk_...] node test/bench.js
 *
 * BENCH_API_KEY (valid on BOTH servers' database) adds the /api/v1/catalogue key-authenticated case,
 * which is where the original pays an argon2 verification on every request.
 */
const OLD = process.env.OLD_URL ?? 'http://localhost:3100';
const NEW = process.env.NEW_URL ?? 'http://localhost:3200';
const EMAIL = process.env.BENCH_EMAIL ?? process.env.SEED_ADMIN_EMAIL;
const PASSWORD = process.env.BENCH_PASSWORD ?? process.env.SEED_ADMIN_PASSWORD;
const API_KEY = process.env.BENCH_API_KEY;
const CONCURRENCY = Number(process.env.BENCH_CONCURRENCY ?? 20);
const REQUESTS = Number(process.env.BENCH_REQUESTS ?? 600);

async function login(base) {
  const res = await fetch(`${base}/auth/login`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email: EMAIL, password: PASSWORD }),
  });
  return (await res.json()).accessToken;
}

const percentile = (sorted, p) => sorted[Math.min(sorted.length - 1, Math.floor((p / 100) * sorted.length))];

async function bench(base, path, headers) {
  // Warm-up (JIT, connection pool, and — for the port — the cache).
  for (let i = 0; i < 5; i++) await (await fetch(base + path, { headers })).arrayBuffer();

  const latencies = [];
  let next = 0;
  let bytes = 0;
  let errors = 0;
  const started = performance.now();

  async function worker() {
    while (next < REQUESTS) {
      next++;
      const t0 = performance.now();
      try {
        const res = await fetch(base + path, { headers });
        const buf = await res.arrayBuffer();
        bytes += buf.byteLength;
        if (res.status !== 200) errors++;
      } catch {
        errors++;
      }
      latencies.push(performance.now() - t0);
    }
  }
  await Promise.all(Array.from({ length: CONCURRENCY }, worker));

  const seconds = (performance.now() - started) / 1000;
  latencies.sort((a, b) => a - b);
  return {
    rps: Math.round(REQUESTS / seconds),
    p50: percentile(latencies, 50).toFixed(1),
    p95: percentile(latencies, 95).toFixed(1),
    errors,
    kb: Math.round(bytes / REQUESTS / 1024),
  };
}

(async () => {
  const [tOld, tNew] = [await login(OLD), await login(NEW)];
  const jwt = (t) => ({ authorization: `Bearer ${t}` });

  const cases = [
    ['/products', jwt(tOld), jwt(tNew)],
    ['/locations', jwt(tOld), jwt(tNew)],
    ['/workstreams', jwt(tOld), jwt(tNew)],
    ['/categories', jwt(tOld), jwt(tNew)],
    ['/dashboard', jwt(tOld), jwt(tNew)],
    ['/reports/low-stock', jwt(tOld), jwt(tNew)],
    ['/reports/inventory-valuation', jwt(tOld), jwt(tNew)],
    ['/auth/me', jwt(tOld), jwt(tNew)],
  ];
  if (API_KEY) cases.push(['/api/v1/catalogue', { 'x-api-key': API_KEY }, { 'x-api-key': API_KEY }]);

  console.log(`concurrency ${CONCURRENCY}, ${REQUESTS} requests per endpoint per server\n`);
  console.log('endpoint'.padEnd(30), 'old req/s'.padStart(10), 'new req/s'.padStart(10), 'speedup'.padStart(9), '  p50 old→new (ms)   p95 old→new (ms)  KB/resp old→new');
  for (const [path, hOld, hNew] of cases) {
    const a = await bench(OLD, path, hOld);
    const b = await bench(NEW, path, hNew);
    const flag = a.errors || b.errors ? `  errors old=${a.errors} new=${b.errors}` : '';
    console.log(
      path.padEnd(30),
      String(a.rps).padStart(10),
      String(b.rps).padStart(10),
      `${(b.rps / a.rps).toFixed(1)}x`.padStart(9),
      `  ${a.p50.padStart(6)} → ${b.p50.padEnd(6)}     ${a.p95.padStart(6)} → ${b.p95.padEnd(6)}     ${String(a.kb).padStart(4)} → ${b.kb}${flag}`,
    );
  }
})();
