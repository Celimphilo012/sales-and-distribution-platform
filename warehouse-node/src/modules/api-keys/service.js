'use strict';

const { randomBytes } = require('crypto');
const argon2 = require('argon2');
const { notFound } = require('../../core/errors');
const { TAGS } = require('../../core/cache/cache');

const KEY_SELECT = {
  id: true,
  name: true,
  scopes: true,
  isActive: true,
  createdAt: true,
  lastUsedAt: true,
  createdBy: true,
};

function createApiKeysService({ prisma, cache }) {
  const findAll = () => prisma.apiKey.findMany({ select: KEY_SELECT, orderBy: { createdAt: 'asc' } });

  async function getExisting(id) {
    const key = await prisma.apiKey.findUnique({ where: { id }, select: KEY_SELECT });
    if (!key) throw notFound(`API key ${id} not found`);
    return key;
  }

  /**
   * The raw key is generated here, hashed with argon2 (same as a password), and only the hash is
   * persisted — this is the ONE moment the raw value exists outside the caller's own storage.
   */
  async function create(dto, createdBy) {
    const rawKey = `whk_${randomBytes(32).toString('base64url')}`;
    const keyHash = await argon2.hash(rawKey);

    const created = await prisma.apiKey.create({
      data: { name: dto.name, keyHash, scopes: dto.scopes, createdBy },
      select: KEY_SELECT,
    });
    await cache.invalidate(TAGS.API_KEYS);
    return { ...created, rawKey };
  }

  async function revoke(id) {
    await getExisting(id);
    const revoked = await prisma.apiKey.update({ where: { id }, data: { isActive: false }, select: KEY_SELECT });
    // The verified-key cache must forget this key immediately, not at TTL expiry.
    await cache.invalidate(TAGS.API_KEYS);
    return revoked;
  }

  return { findAll, getExisting, create, revoke };
}

module.exports = { createApiKeysService };
