import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Location, Prisma } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { WarehousesService } from '../warehouses/warehouses.service';
import { CreateLocationDto } from './dto/create-location.dto';
import { CreateChildLocationDto } from './dto/create-child-location.dto';
import { UpdateLocationDto } from './dto/update-location.dto';
import { MoveLocationDto } from './dto/move-location.dto';
import { CreateLevelsDto } from './dto/create-levels.dto';
import { ListLocationsQueryDto } from './dto/list-locations-query.dto';

interface RawLocationRow {
  id: string;
  warehouse_id: string;
  parent_id: string | null;
  name: string;
  code: string;
  location_type: string;
  description: string | null;
  is_active: boolean | number;
  created_at: Date;
  updated_at: Date;
  depth: number;
}

export interface LocationWithDepth extends Location {
  depth: number;
}

function mapRow(row: RawLocationRow): LocationWithDepth {
  return {
    id: row.id,
    warehouseId: row.warehouse_id,
    parentId: row.parent_id,
    name: row.name,
    code: row.code,
    locationType: row.location_type,
    description: row.description,
    // MySQL/MariaDB has no native boolean — `is_active` is TINYINT(1), and
    // $queryRaw (unlike Prisma's normal typed queries) returns the driver's
    // raw 0/1 rather than coercing it to a JS boolean.
    isActive: Boolean(row.is_active),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    depth: Number(row.depth),
  };
}

@Injectable()
export class LocationsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly warehousesService: WarehousesService,
  ) {}

  findAll(query: ListLocationsQueryDto = {}) {
    return this.prisma.location.findMany({
      where: {
        warehouseId: query.warehouseId,
        parentId: query.rootOnly ? null : query.parentId,
        isActive: query.includeInactive ? undefined : true,
      },
      orderBy: { name: 'asc' },
    });
  }

  async getExisting(id: string) {
    const location = await this.prisma.location.findUnique({ where: { id } });
    if (!location) throw new NotFoundException(`Location ${id} not found`);
    return location;
  }

  async findOne(id: string) {
    return this.getExisting(id);
  }

  /**
   * Stock can only be held at leaf locations (Phase 1D part 2 policy,
   * resolving Open Decision #3): receiving/transfer/adjustment/count
   * locations must have zero children, active or not. Used by inventory
   * modules that move or count stock — not by LocationsController itself,
   * which has no opinion on where stock may sit.
   */
  async assertLeaf(locationId: string) {
    const location = await this.getExisting(locationId);
    const childCount = await this.prisma.location.count({ where: { parentId: locationId } });
    if (childCount > 0) {
      throw new BadRequestException(
        `Location "${location.name}" (${locationId}) is not a leaf location — it has ${childCount} child location(s). Stock can only be held at leaf locations.`,
      );
    }
    return location;
  }

  async children(parentId: string, includeInactive = false) {
    await this.getExisting(parentId);
    return this.prisma.location.findMany({
      where: { parentId, isActive: includeInactive ? undefined : true },
      orderBy: { name: 'asc' },
    });
  }

  /**
   * Recursive subtree read (§G) — Prisma has no native recursive CTE, so
   * this goes through $queryRaw with a tagged template, which
   * parameterises `rootId` safely (never string-concatenated SQL).
   * Returns the root itself plus every descendant, each annotated with its
   * depth relative to the root (0 = root).
   */
  async subtree(rootId: string, includeInactive = false): Promise<LocationWithDepth[]> {
    await this.getExisting(rootId);

    const activeFilter = includeInactive ? Prisma.empty : Prisma.sql`WHERE is_active = true`;

    const rows = await this.prisma.$queryRaw<RawLocationRow[]>`
      WITH RECURSIVE tree AS (
        SELECT *, 0 AS depth FROM locations WHERE id = ${rootId}
        UNION ALL
        SELECT l.*, t.depth + 1 AS depth
        FROM locations l
        INNER JOIN tree t ON l.parent_id = t.id
      )
      SELECT * FROM tree
      ${activeFilter}
      ORDER BY depth ASC, name ASC
    `;

    return rows.map(mapRow);
  }

  async create(dto: CreateLocationDto) {
    const { warehouseId, parentId } = await this.resolveWarehouseAndParent(
      dto.warehouseId,
      dto.parentId,
    );
    return this.insertLocation(warehouseId, parentId, dto);
  }

  async addChild(parentId: string, dto: CreateChildLocationDto) {
    const parent = await this.getExisting(parentId);
    return this.insertLocation(parent.warehouseId, parent.id, dto);
  }

  async update(id: string, dto: UpdateLocationDto) {
    await this.getExisting(id);

    try {
      return await this.prisma.location.update({
        where: { id },
        data: {
          name: dto.name,
          code: dto.code,
          locationType: dto.locationType,
          description: dto.description,
          isActive: dto.isActive,
        },
      });
    } catch (error) {
      throw this.translateUniqueViolation(error);
    }
  }

  async move(id: string, dto: MoveLocationDto) {
    const location = await this.getExisting(id);

    if (dto.parentId === null) {
      return this.prisma.location.update({ where: { id }, data: { parentId: null } });
    }

    if (dto.parentId === id) {
      throw new BadRequestException('A location cannot be its own parent');
    }

    const newParent = await this.getExisting(dto.parentId);
    if (newParent.warehouseId !== location.warehouseId) {
      throw new BadRequestException(
        'Cannot move a location to a parent in a different warehouse',
      );
    }
    await this.assertNoCycle(id, dto.parentId);

    return this.prisma.location.update({ where: { id }, data: { parentId: dto.parentId } });
  }

  async remove(id: string) {
    await this.getExisting(id);
    // Structural reference data is soft-deleted (rule 10) — future
    // inventory_balances keep a valid historical location reference.
    return this.prisma.location.update({ where: { id }, data: { isActive: false } });
  }

  /**
   * "Create N levels" convenience (§G): loops plain inserts of sibling
   * child locations under `parentId`. Deliberately unbounded — count has
   * no upper limit (rule 5).
   */
  async generateLevels(parentId: string, dto: CreateLevelsDto) {
    const parent = await this.getExisting(parentId);

    const locationType = dto.locationType ?? 'LEVEL';
    const namePrefix = dto.namePrefix ?? 'Level';
    const codePrefix = dto.codePrefix ?? locationType.charAt(0).toUpperCase();
    const startIndex = dto.startIndex ?? 1;

    const rows = Array.from({ length: dto.count }, (_, offset) => {
      const n = startIndex + offset;
      return {
        warehouseId: parent.warehouseId,
        parentId: parent.id,
        name: `${namePrefix} ${n}`,
        code: `${parent.code}-${codePrefix}${n}`,
        locationType,
      };
    });

    try {
      return await this.prisma.$transaction(
        rows.map((data) => this.prisma.location.create({ data })),
      );
    } catch (error) {
      throw this.translateUniqueViolation(error);
    }
  }

  private async insertLocation(
    warehouseId: string,
    parentId: string | null,
    dto: { name: string; code: string; locationType: string; description?: string },
  ) {
    try {
      return await this.prisma.location.create({
        data: {
          warehouseId,
          parentId,
          name: dto.name,
          code: dto.code,
          locationType: dto.locationType,
          description: dto.description,
        },
      });
    } catch (error) {
      throw this.translateUniqueViolation(error);
    }
  }

  private async resolveWarehouseAndParent(warehouseId?: string, parentId?: string) {
    if (parentId) {
      const parent = await this.getExisting(parentId);
      if (warehouseId && warehouseId !== parent.warehouseId) {
        throw new BadRequestException('warehouseId does not match the parent location\'s warehouse');
      }
      return { warehouseId: parent.warehouseId, parentId: parent.id as string | null };
    }

    if (!warehouseId) {
      throw new BadRequestException('Either warehouseId or parentId is required');
    }
    await this.warehousesService.getExisting(warehouseId);
    return { warehouseId, parentId: null as string | null };
  }

  private async assertNoCycle(locationId: string, proposedParentId: string) {
    let currentId: string | null = proposedParentId;
    const visited = new Set<string>();

    while (currentId) {
      if (currentId === locationId) {
        throw new ConflictException(
          'Cannot assign this parent: it would create a cycle in the location tree',
        );
      }
      if (visited.has(currentId)) break;
      visited.add(currentId);

      const parent: { parentId: string | null } | null = await this.prisma.location.findUnique({
        where: { id: currentId },
        select: { parentId: true },
      });
      currentId = parent?.parentId ?? null;
    }
  }

  private translateUniqueViolation(error: unknown) {
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
      return new ConflictException('A location with this code already exists in this warehouse');
    }
    return error;
  }
}
