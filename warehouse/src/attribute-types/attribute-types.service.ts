import { ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { CreateAttributeTypeDto } from './dto/create-attribute-type.dto';
import { UpdateAttributeTypeDto } from './dto/update-attribute-type.dto';
import { ListAttributeTypesQueryDto } from './dto/list-attribute-types-query.dto';

@Injectable()
export class AttributeTypesService {
  constructor(private readonly prisma: PrismaService) {}

  findAll(query: ListAttributeTypesQueryDto = {}) {
    return this.prisma.attributeType.findMany({
      where: { isActive: query.includeInactive ? undefined : true },
      orderBy: { name: 'asc' },
    });
  }

  async getExisting(id: string) {
    const attributeType = await this.prisma.attributeType.findUnique({ where: { id } });
    if (!attributeType) throw new NotFoundException(`Attribute type ${id} not found`);
    return attributeType;
  }

  async findOne(id: string) {
    return this.getExisting(id);
  }

  async create(dto: CreateAttributeTypeDto) {
    try {
      return await this.prisma.attributeType.create({
        data: {
          name: dto.name,
          code: dto.code,
          dataType: dto.dataType ?? 'TEXT',
          unit: dto.unit,
        },
      });
    } catch (error) {
      throw this.translateUniqueViolation(error);
    }
  }

  async update(id: string, dto: UpdateAttributeTypeDto) {
    await this.getExisting(id);

    try {
      return await this.prisma.attributeType.update({
        where: { id },
        data: {
          name: dto.name,
          code: dto.code,
          dataType: dto.dataType,
          unit: dto.unit,
          isActive: dto.isActive,
        },
      });
    } catch (error) {
      throw this.translateUniqueViolation(error);
    }
  }

  async remove(id: string) {
    await this.getExisting(id);
    // Reference data is soft-deleted (rule 10) — products keep a valid
    // historical attribute-type reference even after it's deactivated.
    return this.prisma.attributeType.update({ where: { id }, data: { isActive: false } });
  }

  private translateUniqueViolation(error: unknown) {
    if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
      return new ConflictException('An attribute type with this code already exists');
    }
    return error;
  }
}
