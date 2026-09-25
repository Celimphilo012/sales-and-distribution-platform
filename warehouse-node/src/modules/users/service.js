'use strict';

const argon2 = require('argon2');
const { conflict, notFound, unauthorized } = require('../../core/errors');
const { TAGS } = require('../../core/cache/cache');

const USER_SELECT = {
  id: true,
  email: true,
  fullName: true,
  status: true,
  createdAt: true,
  updatedAt: true,
  userRoles: { select: { role: { select: { id: true, name: true } } } },
};

function present(user) {
  const { userRoles, ...rest } = user;
  return { ...rest, roles: userRoles.map((ur) => ur.role) };
}

function createUsersService({ prisma, cache }) {
  async function findAll() {
    const users = await prisma.user.findMany({ select: USER_SELECT, orderBy: { createdAt: 'asc' } });
    return users.map(present);
  }

  async function getExisting(id) {
    const user = await prisma.user.findUnique({ where: { id }, select: USER_SELECT });
    if (!user) throw notFound(`User ${id} not found`);
    return present(user);
  }

  const findOne = getExisting;

  async function create(dto) {
    const existing = await prisma.user.findUnique({ where: { email: dto.email } });
    if (existing) throw conflict('A user with this email already exists');

    const passwordHash = await argon2.hash(dto.password);
    const user = await prisma.user.create({
      data: {
        email: dto.email,
        passwordHash,
        fullName: dto.fullName,
        userRoles: dto.roleIds ? { create: dto.roleIds.map((roleId) => ({ roleId })) } : undefined,
      },
      select: USER_SELECT,
    });
    await cache.invalidate(TAGS.PERMISSIONS);
    return present(user);
  }

  async function update(id, dto) {
    await getExisting(id);
    const passwordHash = dto.password ? await argon2.hash(dto.password) : undefined;

    const user = await prisma.$transaction(async (tx) => {
      if (dto.roleIds) await tx.userRole.deleteMany({ where: { userId: id } });
      return tx.user.update({
        where: { id },
        data: {
          fullName: dto.fullName ?? undefined,
          status: dto.status ?? undefined,
          passwordHash,
          userRoles: dto.roleIds ? { create: dto.roleIds.map((roleId) => ({ roleId })) } : undefined,
        },
        select: USER_SELECT,
      });
    });

    await cache.invalidate(TAGS.PERMISSIONS);
    return present(user);
  }

  /**
   * Self-service change-password — distinct from update()'s admin reset: any authenticated
   * user changing their OWN password, gated by proving they know the current one.
   */
  async function changeOwnPassword(userId, dto) {
    const user = await prisma.user.findUnique({ where: { id: userId } });
    if (!user) throw notFound(`User ${userId} not found`);

    if (!(await argon2.verify(user.passwordHash, dto.currentPassword))) {
      throw unauthorized('Current password is incorrect');
    }

    const passwordHash = await argon2.hash(dto.newPassword);
    await prisma.user.update({ where: { id: userId }, data: { passwordHash } });
    return { success: true };
  }

  async function remove(id) {
    await getExisting(id);
    // Users are never hard-deleted; deactivate so audit_logs / created records keep a valid author.
    const user = await prisma.user.update({ where: { id }, data: { status: 'INACTIVE' }, select: USER_SELECT });
    return present(user);
  }

  return { findAll, findOne, getExisting, create, update, changeOwnPassword, remove };
}

module.exports = { createUsersService };
