'use strict';

const argon2 = require('argon2');
const { badRequest, conflict, notFound, unauthorized } = require('../../core/errors');
const { TAGS } = require('../../core/cache/cache');
const { cols, groupBy } = require('../../core/models');

// The password hash and TOTP secret never leave this service.
const USER_FIELDS = ['id', 'email', 'fullName', 'phone', 'notifyChannel', 'mfaMethod', 'status', 'createdAt', 'updatedAt'];

/**
 * Phone numbers are stored in international (E.164) form, "+26876123456" — what httpSMS needs.
 * Spaces, dashes, dots and brackets are dropped; null/'' clears the number.
 */
function normalizePhone(raw) {
  if (raw === undefined) return undefined;
  if (raw === null || String(raw).trim() === '') return null;
  const phone = String(raw).replace(/[\s().-]/g, '');
  if (!/^\+[1-9]\d{6,14}$/.test(phone)) {
    throw badRequest('phone must be in international format with a country code, e.g. +268 7612 3456');
  }
  return phone;
}

function createUsersService({ db, models, cache, access }) {
  /** Attaches roles: [{ id, name }] and warehouses: [{ id, name, code }] — one query each for the list. */
  async function present(users) {
    if (users.length === 0) return users;
    const ids = users.map((u) => u.id);
    const [roleRows, warehousesByUser] = await Promise.all([
      db.query(
        `SELECT ur.user_id AS userId, r.id, r.name
           FROM user_roles ur JOIN roles r ON r.id = ur.role_id
          WHERE ur.user_id IN (?)`,
        [ids],
      ),
      access.listForUsers(ids),
    ]);
    const rolesByUser = groupBy(roleRows, 'userId');
    return users.map((u) => ({
      ...u,
      roles: (rolesByUser.get(u.id) ?? []).map(({ id, name }) => ({ id, name })),
      warehouses: warehousesByUser.get(u.id) ?? [],
    }));
  }

  async function findAll() {
    const users = await db.query(`SELECT ${cols('user', 'u', USER_FIELDS)} FROM users u ORDER BY u.created_at ASC`);
    return present(users);
  }

  async function getExisting(id) {
    const user = await db.one(`SELECT ${cols('user', 'u', USER_FIELDS)} FROM users u WHERE u.id = ?`, [id]);
    if (!user) throw notFound(`User ${id} not found`);
    const [presented] = await present([user]);
    return presented;
  }

  /** notifyChannel SMS needs a phone; SMS sign-in codes need a phone. Shared by admin + self edits. */
  function assertContactRules(next) {
    if (next.notifyChannel === 'SMS' && !next.phone) {
      throw badRequest('Add a phone number to receive notifications by SMS');
    }
    if (next.mfaMethod === 'SMS' && !next.phone) {
      throw conflict('This user signs in with SMS codes — switch their sign-in verification off or to another method before removing the phone number');
    }
  }

  async function create(dto) {
    const existing = await db.one('SELECT id FROM users WHERE email = ?', [dto.email]);
    if (existing) throw conflict('A user with this email already exists');

    const phone = normalizePhone(dto.phone) ?? null;
    const notifyChannel = dto.notifyChannel ?? 'EMAIL';
    assertContactRules({ phone, notifyChannel, mfaMethod: 'NONE' });

    const passwordHash = await argon2.hash(dto.password);
    const id = await db.transaction(async (tx) => {
      const user = await models.insert(
        'user',
        { email: dto.email, passwordHash, fullName: dto.fullName, phone, notifyChannel },
        tx,
      );
      if (dto.roleIds?.length) {
        await models.insertMany('userRole', dto.roleIds.map((roleId) => ({ userId: user.id, roleId })), tx);
      }
      return user.id;
    });
    await cache.invalidate(TAGS.PERMISSIONS);
    return getExisting(id);
  }

  async function update(id, dto) {
    const current = await getExisting(id);
    const phone = normalizePhone(dto.phone);
    assertContactRules({
      phone: phone === undefined ? current.phone : phone,
      notifyChannel: dto.notifyChannel ?? current.notifyChannel,
      mfaMethod: current.mfaMethod,
    });
    const passwordHash = dto.password ? await argon2.hash(dto.password) : undefined;

    await db.transaction(async (tx) => {
      if (dto.roleIds) await db.exec('DELETE FROM user_roles WHERE user_id = ?', [id], tx);
      await models.update(
        'user',
        id,
        {
          fullName: dto.fullName ?? undefined,
          status: dto.status ?? undefined,
          phone,
          notifyChannel: dto.notifyChannel ?? undefined,
          passwordHash,
        },
        'User',
        tx,
      );
      if (dto.roleIds?.length) {
        await models.insertMany('userRole', dto.roleIds.map((roleId) => ({ userId: id, roleId })), tx);
      }
    });

    await cache.invalidate(TAGS.PERMISSIONS);
    return getExisting(id);
  }

  /** Self-service profile: name, phone, how to receive notifications. */
  async function updateOwnProfile(userId, dto) {
    const current = await getExisting(userId);
    const phone = normalizePhone(dto.phone);
    const nextPhone = phone === undefined ? current.phone : phone;
    if (current.mfaMethod === 'SMS' && phone !== undefined && phone !== current.phone) {
      throw conflict('You sign in with SMS codes — turn sign-in verification off (or switch method) before changing your phone number');
    }
    assertContactRules({
      phone: nextPhone,
      notifyChannel: dto.notifyChannel ?? current.notifyChannel,
      mfaMethod: current.mfaMethod,
    });
    await models.update(
      'user',
      userId,
      { fullName: dto.fullName ?? undefined, phone, notifyChannel: dto.notifyChannel ?? undefined },
      'User',
    );
    return getExisting(userId);
  }

  /**
   * Self-service change-password — distinct from update()'s admin reset: any authenticated
   * user changing their OWN password, gated by proving they know the current one.
   */
  async function changeOwnPassword(userId, dto) {
    const user = await db.one('SELECT id, password_hash AS passwordHash FROM users WHERE id = ?', [userId]);
    if (!user) throw notFound(`User ${userId} not found`);

    if (!(await argon2.verify(user.passwordHash, dto.currentPassword))) {
      throw unauthorized('Current password is incorrect');
    }

    const passwordHash = await argon2.hash(dto.newPassword);
    await models.update('user', userId, { passwordHash }, 'User');
    return { success: true };
  }

  /** Admin: turns a user's sign-in verification off (lost phone / new device). They can re-enrol. */
  async function resetMfa(id) {
    await getExisting(id);
    await models.update('user', id, { mfaMethod: 'NONE', totpSecret: null }, 'User');
    return getExisting(id);
  }

  async function setWarehouses(id, warehouseIds) {
    await getExisting(id);
    await access.setForUser(id, warehouseIds);
    return getExisting(id);
  }

  async function remove(id) {
    await getExisting(id);
    // Users are never hard-deleted; deactivate so audit_logs / created records keep a valid author.
    await models.update('user', id, { status: 'INACTIVE' }, 'User');
    return getExisting(id);
  }

  return {
    findAll,
    findOne: getExisting,
    getExisting,
    create,
    update,
    updateOwnProfile,
    changeOwnPassword,
    resetMfa,
    setWarehouses,
    remove,
  };
}

module.exports = { createUsersService, normalizePhone };
