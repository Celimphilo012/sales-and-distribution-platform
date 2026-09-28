'use strict';

const { randomBytes } = require('crypto');
const argon2 = require('argon2');
const { notFound } = require('../../core/errors');
const { TAGS } = require('../../core/cache/cache');
const { cols, hydrate } = require('../../core/models');

// The key hash never leaves this service.
const KEY_FIELDS = ['id', 'name', 'scopes', 'isActive', 'createdAt', 'lastUsedAt', 'createdBy'];

function createApiKeysService({ db, models, cache }) {
  const findAll = async () =>
    hydrate('apiKey', await db.query(`SELECT ${cols('apiKey', 'k', KEY_FIELDS)} FROM api_keys k ORDER BY k.created_at ASC`));

  async function getExisting(id) {
    const key = await db.one(`SELECT ${cols('apiKey', 'k', KEY_FIELDS)} FROM api_keys k WHERE k.id = ?`, [id]);
    if (!key) throw notFound(`API key ${id} not found`);
    return hydrate('apiKey', key);
  }

  /**
   * The raw key is generated here, hashed with argon2 (same as a password), and only the hash is
   * persisted — this is the ONE moment the raw value exists outside the caller's own storage.
   */
  async function create(dto, createdBy) {
    const rawKey = `whk_${randomBytes(32).toString('base64url')}`;
    const keyHash = await argon2.hash(rawKey);

    const row = await models.insert('apiKey', { name: dto.name, keyHash, scopes: dto.scopes, createdBy });
    await cache.invalidate(TAGS.API_KEYS);
    return { ...(await getExisting(row.id)), rawKey };
  }

  async function revoke(id) {
    await getExisting(id);
    await db.exec('UPDATE api_keys SET is_active = false WHERE id = ?', [id]);
    // The verified-key cache must forget this key immediately, not at TTL expiry.
    await cache.invalidate(TAGS.API_KEYS);
    return getExisting(id);
  }

  return { findAll, getExisting, create, revoke };
}

module.exports = { createApiKeysService };
