import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { CreateCategoryDto } from './dto/create-category.dto';
import { UpdateCategoryDto } from './dto/update-category.dto';

interface FindAllOptions {
  includeInactive?: boolean;
  parentId?: string;
}

@Injectable()
export class CategoriesService {
  constructor(private readonly prisma: PrismaService) {}

  findAll(options: FindAllOptions = {}) {
    return this.prisma.category.findMany({
      where: {
        isActive: options.includeInactive ? undefined : true,
        parentId: options.parentId,
      },
      orderBy: { name: 'asc' },
    });
  }

  async getExisting(id: string) {
    const category = await this.prisma.category.findUnique({ where: { id } });
    if (!category) throw new NotFoundException(`Category ${id} not found`);
    return category;
  }

  async findOne(id: string) {
    return this.getExisting(id);
  }

  async create(dto: CreateCategoryDto) {
    if (dto.parentId) {
      await this.getExisting(dto.parentId);
    }

    return this.prisma.category.create({
      data: { name: dto.name, parentId: dto.parentId ?? null },
    });
  }

  async update(id: string, dto: UpdateCategoryDto) {
    await this.getExisting(id);

    if (dto.parentId !== undefined && dto.parentId !== null) {
      if (dto.parentId === id) {
        throw new BadRequestException('A category cannot be its own parent');
      }
      await this.getExisting(dto.parentId);
      await this.assertNoCycle(id, dto.parentId);
    }

    return this.prisma.category.update({
      where: { id },
      data: {
        name: dto.name,
        isActive: dto.isActive,
        ...(dto.parentId !== undefined ? { parentId: dto.parentId } : {}),
      },
    });
  }

  async remove(id: string) {
    await this.getExisting(id);
    // Reference data is soft-deleted (rule 10) — products keep a valid
    // historical category reference even after it's deactivated.
    return this.prisma.category.update({ where: { id }, data: { isActive: false } });
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
