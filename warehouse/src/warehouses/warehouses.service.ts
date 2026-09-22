import { ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { CreateWarehouseDto } from './dto/create-warehouse.dto';
import { UpdateWarehouseDto } from './dto/update-warehouse.dto';
import { ListWarehousesQueryDto } from './dto/list-warehouses-query.dto';

@Injectable()
export class WarehousesService {
  constructor(private readonly prisma: PrismaService) {}

  findAll(query: ListWarehousesQueryDto = {}) {
    return this.prisma.warehouse.findMany({
      where: { isActive: query.includeInactive ? undefined : true },
      orderBy: { name: 'asc' },
    });
  }

  async getExisting(id: string) {
    const warehouse = await this.prisma.warehouse.findUnique({ where: { id } });
    if (!warehouse) throw new NotFoundException(`Warehouse ${id} not found`);
    return warehouse;
  }

  /** DB-level COUNT for the reports dashboard's catalogue summary. */
  countActive() {
    return this.prisma.warehouse.count({ where: { isActive: true } });
  }

  async findOne(id: string) {
    return this.getExisting(id);
  }

  async create(dto: CreateWarehouseDto) {
    const existing = await this.prisma.warehouse.findUnique({ where: { code: dto.code } });
    if (existing) throw new ConflictException('A warehouse with this code already exists');

    return this.prisma.warehouse.create({ data: { name: dto.name, code: dto.code } });
  }

  async update(id: string, dto: UpdateWarehouseDto) {
    await this.getExisting(id);

    if (dto.code) {
      const existing = await this.prisma.warehouse.findUnique({ where: { code: dto.code } });
      if (existing && existing.id !== id) {
        throw new ConflictException('A warehouse with this code already exists');
      }
    }

    return this.prisma.warehouse.update({
      where: { id },
      data: { name: dto.name, code: dto.code, isActive: dto.isActive },
    });
  }

  async remove(id: string) {
    await this.getExisting(id);
    // Structural reference data is soft-deleted (rule 10) — locations (and
    // later inventory_balances) keep a valid historical warehouse reference.
    return this.prisma.warehouse.update({ where: { id }, data: { isActive: false } });
  }
}
