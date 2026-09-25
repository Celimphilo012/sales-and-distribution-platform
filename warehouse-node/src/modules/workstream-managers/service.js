'use strict';

const { Prisma } = require('@prisma/client');
const { conflict, forbidden, notFound } = require('../../core/errors');
const { TAGS } = require('../../core/cache/cache');

const MANAGER_SELECT = {
  id: true,
  userId: true,
  workstreamId: true,
  createdAt: true,
  user: { select: { id: true, email: true, fullName: true, status: true } },
};

/**
 * Owns the workstream_managers assignment table and the scoping check it drives. A user with ANY
 * assignment row is restricted, for catalogue mutations (categories + products), to only their
 * assigned workstream(s); a user with none is unscoped. Data-driven, never keyed off a role name
 * (CLAUDE.md rule 1).
 *
 * Depends only on Prisma + the cache so Workstreams/Categories/Products can all use it for scoping
 * without a circular dependency.
 */
function createWorkstreamManagersService({ prisma, cache, config }) {
  const listForWorkstream = (workstreamId) =>
    prisma.workstreamManager.findMany({
      where: { workstreamId },
      select: MANAGER_SELECT,
      orderBy: { createdAt: 'asc' },
    });

  const listForUser = (userId) =>
    prisma.workstreamManager.findMany({
      where: { userId },
      select: {
        id: true,
        workstreamId: true,
        createdAt: true,
        workstream: { select: { id: true, name: true, code: true } },
      },
      orderBy: { createdAt: 'asc' },
    });

  /**
   * The workstream IDs a user is scoped to. Empty means "unscoped". Read on nearly every catalogue
   * request (list scoping + every mutation's scope check), so it is cached and invalidated on
   * assign/unassign.
   */
  const getAssignedWorkstreamIds = (userId) =>
    cache.wrap(`scopes:${userId}`, { ttlMs: config.cache.referenceTtlMs, tags: [TAGS.SCOPES] }, async () => {
      const rows = await prisma.workstreamManager.findMany({ where: { userId }, select: { workstreamId: true } });
      return rows.map((r) => r.workstreamId);
    });

  /**
   * The enforcement point — called before every catalogue mutation with the workstream the target
   * row belongs to. A no-op for an unscoped user; throws for a scoped user acting outside their
   * assigned workstream(s).
   */
  async function assertScopedAccess(userId, workstreamId) {
    const assignedIds = await getAssignedWorkstreamIds(userId);
    if (assignedIds.length === 0) return;
    if (!assignedIds.includes(workstreamId)) throw forbidden('You are not assigned to manage this workstream');
  }

  async function assign(workstreamId, userId) {
    const [workstream, user] = await Promise.all([
      prisma.workstream.findUnique({ where: { id: workstreamId } }),
      prisma.user.findUnique({ where: { id: userId } }),
    ]);
    if (!workstream) throw notFound(`Workstream ${workstreamId} not found`);
    if (!user) throw notFound(`User ${userId} not found`);

    try {
      const row = await prisma.workstreamManager.create({ data: { workstreamId, userId }, select: MANAGER_SELECT });
      await cache.invalidate(TAGS.SCOPES);
      return row;
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
        throw conflict('This user is already assigned to this workstream');
      }
      throw error;
    }
  }

  async function unassign(workstreamId, userId) {
    const existing = await prisma.workstreamManager.findUnique({
      where: { userId_workstreamId: { userId, workstreamId } },
    });
    if (!existing) throw notFound('This user is not assigned to this workstream');
    await prisma.workstreamManager.delete({ where: { id: existing.id } });
    await cache.invalidate(TAGS.SCOPES);
    return { workstreamId, userId, removed: true };
  }

  return { listForWorkstream, listForUser, getAssignedWorkstreamIds, assertScopedAccess, assign, unassign };
}

module.exports = { createWorkstreamManagersService };
