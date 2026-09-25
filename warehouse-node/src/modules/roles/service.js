'use strict';

const { conflict, notFound } = require('../../core/errors');
const { TAGS } = require('../../core/cache/cache');

const ROLE_SELECT = {
  id: true,
  name: true,
  description: true,
  isSystem: true,
  createdAt: true,
  updatedAt: true,
  rolePermissions: {
    select: { permission: { select: { id: true, key: true, description: true, module: true } } },
  },
};

function present(role) {
  const { rolePermissions, ...rest } = role;
  return { ...rest, permissions: rolePermissions.map((rp) => rp.permission) };
}

function createRolesService({ prisma, cache }) {
  async function findAll() {
    const roles = await prisma.role.findMany({ select: ROLE_SELECT, orderBy: { name: 'asc' } });
    return roles.map(present);
  }

  async function getExisting(id) {
    const role = await prisma.role.findUnique({ where: { id }, select: ROLE_SELECT });
    if (!role) throw notFound(`Role ${id} not found`);
    return present(role);
  }

  async function create(dto) {
    const existing = await prisma.role.findUnique({ where: { name: dto.name } });
    if (existing) throw conflict('A role with this name already exists');

    const role = await prisma.role.create({
      data: { name: dto.name, description: dto.description },
      select: ROLE_SELECT,
    });
    return present(role);
  }

  async function update(id, dto) {
    const existing = await prisma.role.findUnique({ where: { id } });
    if (!existing) throw notFound(`Role ${id} not found`);
    if (existing.isSystem && dto.name) throw conflict('Cannot rename a system role');

    const role = await prisma.role.update({
      where: { id },
      data: { name: dto.name ?? undefined, description: dto.description },
      select: ROLE_SELECT,
    });
    return present(role);
  }

  async function remove(id) {
    const existing = await prisma.role.findUnique({
      where: { id },
      include: { _count: { select: { userRoles: true } } },
    });
    if (!existing) throw notFound(`Role ${id} not found`);
    if (existing.isSystem) throw conflict('Cannot delete a system role');
    if (existing._count.userRoles > 0) throw conflict('Cannot delete a role that is still assigned to users');

    await prisma.role.delete({ where: { id } });
    return { id, deleted: true };
  }

  async function assignPermissions(id, dto) {
    await getExisting(id);

    const role = await prisma.$transaction(async (tx) => {
      await tx.rolePermission.deleteMany({ where: { roleId: id } });
      await tx.rolePermission.createMany({
        data: dto.permissionIds.map((permissionId) => ({ roleId: id, permissionId })),
      });
      return tx.role.findUniqueOrThrow({ where: { id }, select: ROLE_SELECT });
    });

    // Effective permissions changed for every user holding this role.
    await cache.invalidate(TAGS.PERMISSIONS);
    return present(role);
  }

  return { findAll, findOne: getExisting, getExisting, create, update, remove, assignPermissions };
}

module.exports = { createRolesService };
