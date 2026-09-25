import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { WorkstreamsService } from '../workstreams/workstreams.service';
import { WorkstreamManagersService } from '../workstream-managers/workstream-managers.service';
import { CreateCategoryDto } from './dto/create-category.dto';
import { UpdateCategoryDto } from './dto/update-category.dto';

interface FindAllOptions {
  includeInactive?: boolean;
  parentId?: string;
  workstreamId?: string;
}

const CATEGORY_INCLUDE = {
  workstream: { select: { id: true, name: true, code: true } },
};

@Injectable()
export class CategoriesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly workstreamsService: WorkstreamsService,
    private readonly workstreamManagersService: WorkstreamManagersService,
  ) {}

  /** [viewerId], when given, narrows the result to only categories in a workstream that viewer is assigned to — see WorkstreamsService.findAll's own doc comment. */
  async findAll(options: FindAllOptions = {}, viewerId?: string) {
    const workstreamId = await this.effectiveWorkstreamIdFilter(options.workstreamId, viewerId);

    return this.prisma.category.findMany({
      where: {
        isActive: options.includeInactive ? undefined : true,
        parentId: options.parentId,
        workstreamId,
      },
      include: CATEGORY_INCLUDE,
      orderBy: { name: 'asc' },
    });
  }

  /**
   * Intersects an explicit `workstreamId` query filter (if any) with a
   * scoped viewer's assigned workstream(s) (if any) — the single value if
   * both agree, an impossible `{in: []}` if they conflict (an explicit
   * filter for a workstream the viewer isn't assigned to correctly yields
   * zero rows, not an error, since this is a read/list endpoint), or
   * whichever one was actually given when only one applies.
   */
  private async effectiveWorkstreamIdFilter(
    explicit: string | undefined,
    viewerId: string | undefined,
  ): Promise<string | { in: string[] } | undefined> {
    if (!viewerId) return explicit;
    const assignedIds = await this.workstreamManagersService.getAssignedWorkstreamIds(viewerId);
    if (assignedIds.length === 0) return explicit;
    if (!explicit) return { in: assignedIds };
    return assignedIds.includes(explicit) ? explicit : { in: [] };
  }

  async getExisting(id: string) {
    const category = await this.prisma.category.findUnique({ where: { id } });
    if (!category) throw new NotFoundException(`Category ${id} not found`);
    return category;
  }

  /** DB-level COUNT for the reports dashboard's catalogue summary. */
  countActive() {
    return this.prisma.category.count({ where: { isActive: true } });
  }

  /** [viewerId], when given, 403s if that viewer is scoped and this category's workstream isn't one of theirs. */
  async findOne(id: string, viewerId?: string) {
    const category = await this.prisma.category.findUnique({
      where: { id },
      include: CATEGORY_INCLUDE,
    });
    if (!category) throw new NotFoundException(`Category ${id} not found`);
    if (viewerId) await this.workstreamManagersService.assertScopedAccess(viewerId, category.workstreamId);
    return category;
  }

  async create(dto: CreateCategoryDto, actingUserId: string) {
    await this.workstreamsService.getExisting(dto.workstreamId);
    await this.workstreamManagersService.assertScopedAccess(actingUserId, dto.workstreamId);

    if (dto.parentId) {
      const parent = await this.getExisting(dto.parentId);
      if (parent.workstreamId !== dto.workstreamId) {
        throw new BadRequestException(
          "A sub-category must belong to the same workstream as its parent category",
        );
      }
    }

    return this.prisma.category.create({
      data: { name: dto.name, parentId: dto.parentId ?? null, workstreamId: dto.workstreamId },
      include: CATEGORY_INCLUDE,
    });
  }

  async update(id: string, dto: UpdateCategoryDto, actingUserId: string) {
    const existing = await this.getExisting(id);
    // Scoped to the category's CURRENT workstream always — moving it to a
    // new one (below) additionally requires scope over the DESTINATION too,
    // so a manager can't move a category into a workstream they don't hold.
    await this.workstreamManagersService.assertScopedAccess(actingUserId, existing.workstreamId);

    if (dto.workstreamId !== undefined && dto.workstreamId !== existing.workstreamId) {
      await this.workstreamsService.getExisting(dto.workstreamId);
      await this.workstreamManagersService.assertScopedAccess(actingUserId, dto.workstreamId);
      const childCount = await this.prisma.category.count({ where: { parentId: id } });
      if (childCount > 0) {
        throw new BadRequestException(
          'Cannot change the workstream of a category that has sub-categories — move or update the sub-categories first',
        );
      }
    }

    if (dto.parentId !== undefined && dto.parentId !== null) {
      if (dto.parentId === id) {
        throw new BadRequestException('A category cannot be its own parent');
      }
      const parent = await this.getExisting(dto.parentId);
      await this.assertNoCycle(id, dto.parentId);

      const effectiveWorkstreamId = dto.workstreamId ?? existing.workstreamId;
      if (parent.workstreamId !== effectiveWorkstreamId) {
        throw new BadRequestException(
          "A sub-category must belong to the same workstream as its parent category",
        );
      }
    }

    return this.prisma.category.update({
      where: { id },
      data: {
        name: dto.name,
        isActive: dto.isActive,
        workstreamId: dto.workstreamId,
        ...(dto.parentId !== undefined ? { parentId: dto.parentId } : {}),
      },
      include: CATEGORY_INCLUDE,
    });
  }

  async remove(id: string, actingUserId: string) {
    const existing = await this.getExisting(id);
    await this.workstreamManagersService.assertScopedAccess(actingUserId, existing.workstreamId);
    // Reference data is soft-deleted (rule 10) — products keep a valid
    // historical category reference even after it's deactivated.
    return this.prisma.category.update({
      where: { id },
      data: { isActive: false },
      include: CATEGORY_INCLUDE,
    });
  }

  private async assertNoCycle(categoryId: string, proposedParentId: string) {
    let currentId: string | null = proposedParentId;
    const visited = new Set<string>();

    while (currentId) {
      if (currentId === categoryId) {
        throw new ConflictException(
          'Cannot assign this parent: it would create a cycle in the category tree',
        );
      }
      if (visited.has(currentId)) break;
      visited.add(currentId);

      const parent: { parentId: string | null } | null = await this.prisma.category.findUnique({
        where: { id: currentId },
        select: { parentId: true },
      });
      currentId = parent?.parentId ?? null;
    }
  }
}
