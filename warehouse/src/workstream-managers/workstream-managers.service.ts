import { ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';

const MANAGER_SELECT = {
  id: true,
  userId: true,
  workstreamId: true,
  createdAt: true,
  user: { select: { id: true, email: true, fullName: true, status: true } },
} as const;

/**
 * Owns the `workstream_managers` assignment table and the scoping check it
 * drives. A user with ANY assignment row is restricted, for catalogue
 * mutations (categories + products), to only their assigned workstream(s);
 * a user with none is unscoped (today's global behaviour). See the
 * `WorkstreamManager` model's doc comment in schema.prisma for the full
 * design note — this is deliberately data-driven, never keyed off a role
 * name (CLAUDE.md rule 1).
 */
@Injectable()
export class WorkstreamManagersService {
  constructor(private readonly prisma: PrismaService) {}

  listForWorkstream(workstreamId: string) {
    return this.prisma.workstreamManager.findMany({
      where: { workstreamId },
      select: MANAGER_SELECT,
      orderBy: { createdAt: 'asc' },
    });
  }

  listForUser(userId: string) {
    return this.prisma.workstreamManager.findMany({
      where: { userId },
      select: { id: true, workstreamId: true, createdAt: true, workstream: { select: { id: true, name: true, code: true } } },
      orderBy: { createdAt: 'asc' },
    });
  }

  /** The workstream IDs a user is scoped to. Empty means "unscoped" (no restriction). */
  async getAssignedWorkstreamIds(userId: string): Promise<string[]> {
    const rows = await this.prisma.workstreamManager.findMany({
      where: { userId },
      select: { workstreamId: true },
    });
    return rows.map((r) => r.workstreamId);
  }

  /**
   * The enforcement point — called by CategoriesService/ProductsService
   * before every catalogue mutation with the workstream the target row
   * belongs to. A no-op for an unscoped user (no assignment rows at all);
   * throws for a scoped user acting outside their assigned workstream(s).
   */
  async assertScopedAccess(userId: string, workstreamId: string): Promise<void> {
    const assignedIds = await this.getAssignedWorkstreamIds(userId);
    if (assignedIds.length === 0) return;
    if (!assignedIds.includes(workstreamId)) {
      throw new ForbiddenException('You are not assigned to manage this workstream');
    }
  }

  async assign(workstreamId: string, userId: string) {
    // Read the workstream directly via Prisma rather than injecting
    // WorkstreamsService — this module deliberately depends on nothing but
    // PrismaService, so WorkstreamsModule/CategoriesModule/ProductsModule
    // can freely import WorkstreamManagersModule for read-scoping without a
    // circular module dependency back.
    const workstream = await this.prisma.workstream.findUnique({ where: { id: workstreamId } });
    if (!workstream) throw new NotFoundException(`Workstream ${workstreamId} not found`);

    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) throw new NotFoundException(`User ${userId} not found`);

    try {
      const row = await this.prisma.workstreamManager.create({
        data: { workstreamId, userId },
        select: MANAGER_SELECT,
      });
      return row;
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
        throw new ConflictException('This user is already assigned to this workstream');
      }
      throw error;
    }
  }

  async unassign(workstreamId: string, userId: string) {
    const existing = await this.prisma.workstreamManager.findUnique({
      where: { userId_workstreamId: { userId, workstreamId } },
    });
    if (!existing) throw new NotFoundException('This user is not assigned to this workstream');
    await this.prisma.workstreamManager.delete({ where: { id: existing.id } });
    return { workstreamId, userId, removed: true };
  }
}
