import { Injectable, ConflictException, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { WarehousesService } from '../warehouses/warehouses.service';
import { WorkstreamManagersService } from '../workstream-managers/workstream-managers.service';
import { deleteImageFile, imageContentType, imageFilePath } from '../common/uploads/image-storage';
import { CreateWorkstreamDto } from './dto/create-workstream.dto';
import { UpdateWorkstreamDto } from './dto/update-workstream.dto';
import { ListWorkstreamsQueryDto } from './dto/list-workstreams-query.dto';

export const WORKSTREAM_IMAGE_UPLOAD_SUBDIR = 'workstreams';

@Injectable()
export class WorkstreamsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly warehousesService: WarehousesService,
    private readonly workstreamManagersService: WorkstreamManagersService,
  ) {}

  /**
   * [viewerId], when given, narrows the result to only the workstream(s)
   * that viewer is assigned to manage — a no-op for an unscoped user (no
   * assignment rows). Omitted entirely by internal/administrative callers
   * (the dashboard's count, product-import's own template/validation
   * bootstrapping, seed scripts) that intentionally need the full set
   * regardless of who's asking.
   */
  async findAll(query: ListWorkstreamsQueryDto = {}, viewerId?: string) {
    const scopeFilter = await this.scopeFilter(viewerId);
    return this.prisma.workstream.findMany({
      where: {
        warehouseId: query.warehouseId,
        isActive: query.includeInactive ? undefined : true,
        ...scopeFilter,
      },
      orderBy: { name: 'asc' },
    });
  }

  async getExisting(id: string) {
    const workstream = await this.prisma.workstream.findUnique({ where: { id } });
    if (!workstream) throw new NotFoundException(`Workstream ${id} not found`);
    return workstream;
  }

  /** DB-level COUNT for the reports dashboard's catalogue summary. */
  countActive() {
    return this.prisma.workstream.count({ where: { isActive: true } });
  }

  /**
   * [viewerId], when given, 403s if that viewer is scoped and this
   * workstream isn't one of theirs — the single-item counterpart to
   * [findAll]'s list-level filtering ("managers should not see workstreams
   * outside their assignment" applies to direct-by-id access too, not just
   * what shows up in lists).
   */
  async findOne(id: string, viewerId?: string) {
    const workstream = await this.getExisting(id);
    if (viewerId) await this.workstreamManagersService.assertScopedAccess(viewerId, id);
    return workstream;
  }

  private async scopeFilter(viewerId: string | undefined): Promise<{ id?: { in: string[] } }> {
    if (!viewerId) return {};
    const assignedIds = await this.workstreamManagersService.getAssignedWorkstreamIds(viewerId);
    return assignedIds.length === 0 ? {} : { id: { in: assignedIds } };
  }

  async create(dto: CreateWorkstreamDto) {
    await this.warehousesService.getExisting(dto.warehouseId);

    try {
      return await this.prisma.workstream.create({
        data: {
          warehouseId: dto.warehouseId,
          name: dto.name,
          code: dto.code,
          description: dto.description,
          imageUrl: dto.imageUrl,
          contactName: dto.contactName,
          contactEmail: dto.contactEmail,
          contactPhone: dto.contactPhone,
        },
      });
    } catch (error) {
      throw this.translateUniqueViolation(error);
    }
  }

  async update(id: string, dto: UpdateWorkstreamDto) {
    const existing = await this.getExisting(id);

    // Setting an external URL replaces any previously uploaded file — keep
    // the imageUrl/imagePath invariant (at most one set) and clean up the
    // now-orphaned file on disk.
    const clearingImagePath = dto.imageUrl !== undefined && existing.imagePath;

    let updated;
    try {
      updated = await this.prisma.workstream.update({
        where: { id },
        data: {
          name: dto.name,
          code: dto.code,
          description: dto.description,
          imageUrl: dto.imageUrl,
          imagePath: clearingImagePath ? null : undefined,
          contactName: dto.contactName,
          contactEmail: dto.contactEmail,
          contactPhone: dto.contactPhone,
          isActive: dto.isActive,
        },
      });
    } catch (error) {
      throw this.translateUniqueViolation(error);
    }

    if (clearingImagePath && existing.imagePath) {
      deleteImageFile(WORKSTREAM_IMAGE_UPLOAD_SUBDIR, existing.imagePath);
    }
    return updated;
  }

  /** Uploads a device-storage image, replacing any existing url/uploaded image. */
  async uploadImage(id: string, storedFilename: string) {
    const existing = await this.getExisting(id);
    const updated = await this.prisma.workstream.update({
      where: { id },
      data: { imagePath: storedFilename, imageUrl: null },
    });
    if (existing.imagePath) {
      deleteImageFile(WORKSTREAM_IMAGE_UPLOAD_SUBDIR, existing.imagePath);
    }
    return updated;
  }

  /** Clears whichever image (URL or uploaded file) is currently set. */
  async removeImage(id: string) {
    const existing = await this.getExisting(id);
    const updated = await this.prisma.workstream.update({
      where: { id },
      data: { imageUrl: null, imagePath: null },
    });
    if (existing.imagePath) {
      deleteImageFile(WORKSTREAM_IMAGE_UPLOAD_SUBDIR, existing.imagePath);
    }
    return updated;
  }

  /** Resolves the uploaded image's bytes for the GET :id/image/file endpoint. 404s when there's no uploaded file. */
  async getImageFile(id: string): Promise<{ path: string; contentType: string }> {
    const workstream = await this.getExisting(id);
    if (!workstream.imagePath) {
      throw new NotFoundException(`Workstream ${id} has no uploaded image`);
    }
    return {
      path: imageFilePath(WORKSTREAM_IMAGE_UPLOAD_SUBDIR, workstream.imagePath),
      contentType: imageContentType(workstream.imagePath),
    };
  }

  async remove(id: string) {
    await this.getExisting(id);
    // Catalogue-organization reference data is soft-deleted (rule 10) —
    // categories keep a valid historical workstream reference.
    return this.prisma.workstream.update({ where: { id }, data: { isActive: false } });
  }

  private translateUniqueViolation(error: unknown) {
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
      return new ConflictException('A workstream with this code already exists in this warehouse');
    }
    return error;
  }
}
