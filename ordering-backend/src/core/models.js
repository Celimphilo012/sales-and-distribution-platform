'use strict';

const { randomUUID } = require('crypto');
const { notFound } = require('./errors');

/**
 * Table metadata + tiny SQL helpers — the whole data layer (there is no ORM).
 *
 * Every API field is camelCase and every column is its snake_case spelling (sellingPrice ->
 * selling_price), so a model only lists its fields, IN THE ORDER the API has always returned them.
 * SELECTs alias each column back to its field name, so rows come out of mysql2 already API-shaped.
 *
 * Write semantics match what the services were written against:
 *   - a field whose value is `undefined` is left alone; `null` writes NULL;
 *   - ids (UUID v4) and timestamps are generated here, in UTC, never left to column defaults;
 *   - `updatedAt` is bumped on every update of a model that has it.
 */
const MODELS = {
  user: {
    table: 'users',
    fields: [
      'id', 'email', 'passwordHash', 'fullName', 'phone', 'notifyChannel', 'mfaMethod', 'totpSecret', 'status',
      'createdAt', 'updatedAt',
    ],
    defaults: { status: 'ACTIVE', notifyChannel: 'EMAIL', mfaMethod: 'NONE' },
  },
  otpChallenge: {
    table: 'otp_challenges',
    fields: [
      'id', 'userId', 'purpose', 'channel', 'action', 'targetId', 'codeHash', 'pendingSecret', 'attempts',
      'expiresAt', 'consumedAt', 'createdAt',
    ],
    defaults: { attempts: 0 },
  },
  notification: {
    table: 'notifications',
    fields: ['id', 'userId', 'event', 'channel', 'destination', 'subject', 'body', 'status', 'error', 'createdAt'],
  },
  role: { table: 'roles', fields: ['id', 'name', 'description', 'isSystem', 'createdAt', 'updatedAt'], defaults: { isSystem: false } },
  permission: { table: 'permissions', fields: ['id', 'key', 'description', 'module'] },
  rolePermission: { table: 'role_permissions', fields: ['roleId', 'permissionId'], noId: true },
  userRole: { table: 'user_roles', fields: ['userId', 'roleId'], noId: true },
  refreshToken: {
    table: 'refresh_tokens',
    fields: ['id', 'userId', 'tokenHash', 'expiresAt', 'revokedAt', 'replacedByTokenId', 'createdAt'],
  },
  auditLog: {
    table: 'audit_logs',
    fields: ['id', 'userId', 'action', 'entity', 'entityId', 'oldValue', 'newValue', 'createdAt'],
    json: ['oldValue', 'newValue'],
  },
  customer: {
    table: 'customers',
    fields: ['id', 'name', 'phone', 'address', 'locationText', 'status', 'notes', 'createdAt', 'updatedAt'],
    defaults: { status: 'ACTIVE' },
  },
  order: {
    table: 'orders',
    fields: [
      'id', 'orderNumber', 'customerId', 'consultantId', 'salesBatchId', 'status', 'paymentStatus', 'orderDate',
      'deliveryInfo', 'total', 'createdAt', 'updatedAt',
    ],
    defaults: { status: 'DRAFT', paymentStatus: 'UNPAID', total: 0 },
    nowFields: ['orderDate'],
  },
  orderItem: {
    table: 'order_items',
    fields: [
      'id', 'orderId', 'productId', 'productName', 'quantityOrdered', 'quantityFulfilled', 'quantityPicked',
      'quantityPacked', 'unitPrice', 'lineTotal', 'reservedLocationId',
    ],
    defaults: { quantityFulfilled: 0, quantityPicked: 0, quantityPacked: 0 },
  },
  payment: {
    table: 'payments',
    fields: [
      'id', 'orderId', 'amount', 'method', 'reference', 'notes', 'paidAt', 'status', 'recordedBy', 'voidedBy',
      'voidedAt', 'voidReason', 'createdAt', 'updatedAt',
    ],
    defaults: { status: 'RECORDED' },
  },
  orderItemAllocation: {
    table: 'order_item_allocations',
    fields: ['id', 'orderItemId', 'locationId', 'locationLabel', 'quantity', 'position', 'createdAt'],
    defaults: { position: 0 },
  },
  orderStatusHistory: {
    table: 'order_status_history',
    fields: ['id', 'orderId', 'fromStatus', 'toStatus', 'changedBy', 'note', 'createdAt'],
  },
};

const snake = (field) => field.replace(/[A-Z]/g, (c) => `_${c.toLowerCase()}`);

function model(name) {
  const m = MODELS[name];
  if (!m) throw new Error(`Unknown model "${name}"`);
  return m;
}

/**
 * "`a`.`selling_price` AS `sellingPrice`, ..." for a model's fields (all by default).
 * `prefix` namespaces the aliases ("category.name") for joined reads that nest() folds back up.
 */
function cols(name, alias, fields = model(name).fields, prefix = '') {
  return fields.map((f) => `\`${alias}\`.\`${snake(f)}\` AS \`${prefix}${f}\``).join(', ');
}

function parseJson(value) {
  if (typeof value !== 'string') return value ?? null;
  try {
    return JSON.parse(value);
  } catch {
    return value;
  }
}

/** Applies read-side conversions (JSON columns) to rows of `name`, in place. Returns what it was given. */
function hydrate(name, rows) {
  const { json } = model(name);
  if (!json || rows == null) return rows;
  for (const row of Array.isArray(rows) ? rows : [rows]) {
    for (const field of json) if (field in row) row[field] = parseJson(row[field]);
  }
  return rows;
}

/**
 * Folds prefixed aliases back into nested objects: { id, 'category.name': 'X' } ->
 * { id, category: { name: 'X' } }. A nested object whose every value is NULL (a LEFT JOIN
 * that matched nothing) becomes null — an absent optional relation.
 */
function nest(row) {
  const out = {};
  const nested = new Map();
  for (const [key, value] of Object.entries(row)) {
    const dot = key.indexOf('.');
    if (dot === -1) {
      out[key] = value;
      continue;
    }
    const head = key.slice(0, dot);
    if (!nested.has(head)) nested.set(head, {});
    nested.get(head)[key.slice(dot + 1)] = value;
  }
  for (const [head, raw] of nested) {
    const obj = nest(raw);
    out[head] = Object.values(obj).every((v) => v === null) ? null : obj;
  }
  return out;
}

function toColumns(name, data) {
  const { fields, json = [] } = model(name);
  const columns = [];
  const values = [];
  for (const [field, value] of Object.entries(data)) {
    if (value === undefined) continue;
    if (!fields.includes(field)) throw new Error(`Model "${name}" has no field "${field}"`);
    columns.push(`\`${snake(field)}\``);
    values.push(json.includes(field) && value !== null ? JSON.stringify(value) : value);
  }
  return { columns, values };
}

function withInsertDefaults(name, data) {
  const m = model(name);
  const now = new Date();
  const row = { ...(m.defaults ?? {}), ...data };
  if (!m.noId && row.id === undefined) row.id = randomUUID();
  for (const f of ['createdAt', 'updatedAt', ...(m.nowFields ?? [])]) {
    if (m.fields.includes(f) && row[f] === undefined) row[f] = now;
  }
  return row;
}

/**
 * Data-access helpers bound to one db handle. Every method takes an optional `executor` (a
 * transaction's connection) so it can run inside db.transaction().
 */
function createModels(db) {
  async function findById(name, id, executor) {
    const m = model(name);
    const row = await db.one(`SELECT ${cols(name, 't')} FROM \`${m.table}\` t WHERE t.id = ?`, [id], executor);
    return row ? hydrate(name, row) : null;
  }

  /** findById that 404s — `label` is the human name used in the message ("Warehouse"). */
  async function getById(name, id, label, executor) {
    const row = await findById(name, id, executor);
    if (!row) throw notFound(`${label} ${id} not found`);
    return row;
  }

  /** Inserts one row (defaults, id and timestamps filled in) and returns it as stored. */
  async function insert(name, data, executor) {
    const m = model(name);
    const row = withInsertDefaults(name, data);
    const { columns, values } = toColumns(name, row);
    await db.exec(
      `INSERT INTO \`${m.table}\` (${columns.join(', ')}) VALUES (${columns.map(() => '?').join(', ')})`,
      values,
      executor,
    );
    return m.noId ? row : findById(name, row.id, executor);
  }

  /** Multi-row INSERT (no read-back). Rows may list different optional fields. */
  async function insertMany(name, rows, executor) {
    if (rows.length === 0) return;
    const m = model(name);
    const full = rows.map((r) => withInsertDefaults(name, r));
    const fieldSet = [...new Set(full.flatMap((r) => Object.keys(r).filter((k) => r[k] !== undefined)))];
    const { json = [] } = m;
    const values = full.map((r) =>
      fieldSet.map((f) => {
        const v = r[f] === undefined ? null : r[f];
        return json.includes(f) && v !== null ? JSON.stringify(v) : v;
      }),
    );
    await db.exec(
      `INSERT INTO \`${m.table}\` (${fieldSet.map((f) => `\`${snake(f)}\``).join(', ')}) VALUES ?`,
      [values],
      executor,
    );
  }

  /** Updates one row by id and returns it as stored; 404s (`label`) when the id does not exist. */
  async function update(name, id, data, label, executor) {
    const m = model(name);
    const patch = { ...data };
    if (m.fields.includes('updatedAt')) patch.updatedAt = new Date();
    const { columns, values } = toColumns(name, patch);
    if (columns.length) {
      await db.exec(
        `UPDATE \`${m.table}\` SET ${columns.map((c) => `${c} = ?`).join(', ')} WHERE id = ?`,
        [...values, id],
        executor,
      );
    }
    return getById(name, id, label, executor);
  }

  return { findById, getById, insert, insertMany, update };
}

/**
 * Accumulates optional filters. `eq()` with `undefined` adds nothing (an absent query param means
 * "no filter"); with `null` it means IS NULL. `in()` with an empty list matches nothing.
 */
class Where {
  constructor() {
    this.parts = [];
    this.params = [];
  }

  eq(column, value) {
    if (value === undefined) return this;
    if (value === null) this.parts.push(`${column} IS NULL`);
    else {
      this.parts.push(`${column} = ?`);
      this.params.push(value);
    }
    return this;
  }

  in(column, values) {
    if (values === undefined) return this;
    if (values.length === 0) this.parts.push('1 = 0');
    else {
      this.parts.push(`${column} IN (?)`);
      this.params.push(values);
    }
    return this;
  }

  raw(sql, ...params) {
    this.parts.push(sql);
    this.params.push(...params);
    return this;
  }

  get sql() {
    return this.parts.length ? `WHERE ${this.parts.join(' AND ')}` : '';
  }
}

/** Groups rows by a key — used to attach one-to-many children fetched in a single batched query. */
function groupBy(rows, key) {
  const map = new Map();
  for (const row of rows) {
    const k = row[key];
    if (!map.has(k)) map.set(k, []);
    map.get(k).push(row);
  }
  return map;
}

module.exports = { MODELS, createModels, cols, nest, hydrate, parseJson, snake, Where, groupBy };
