import { ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { WarehousesService } from '../warehouses/warehouses.service';
import { CreateWorkstreamDto } from './dto/create-workstream.dto';
import { UpdateWorkstreamDto } from './dto/update-workstream.dto';
import { ListWorkstreamsQueryDto } from './dto/list-workstreams-query.dto';

@Injectable()
export class WorkstreamsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly warehousesService: WarehousesService,
  ) {}

  findAll(query: ListWorkstreamsQueryDto = {}) {
    return this.prisma.workstream.findMany({
      where: {
        warehouseId: query.warehouseId,
        isActive: query.includeInactive ? undefined : true,
      },
      orderBy: { name: 'asc' },
    });
  }

  async getExisting(id: string) {
    const workstream = await this.prisma.workstream.findUnique({ where: { id } });
    if (!workstream) throw new NotFoundException(`Workstream ${id} not found`);
    return workstream;
  }

  async findOne(id: string) {
    return this.getExisting(id);
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
        },
      });
    } catch (error) {
      throw this.translateUniqueViolation(error);
    }
  }

  async update(id: string, dto: UpdateWorkstreamDto) {
    await this.getExisting(id);

    try {
      return await this.prisma.workstream.update({
        where: { id },
        data: {
          name: dto.name,
          code: dto.code,
          description: dto.description,
          isActive: dto.isActive,
        },
      });
    } catch (error) {
      throw this.translateUniqueViolation(error);
    }
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
