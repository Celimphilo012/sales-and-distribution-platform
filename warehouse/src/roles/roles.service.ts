import {
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { CreateRoleDto } from './dto/create-role.dto';
import { UpdateRoleDto } from './dto/update-role.dto';
import { AssignPermissionsDto } from './dto/assign-permissions.dto';

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
} as const;

@Injectable()
export class RolesService {
  constructor(private readonly prisma: PrismaService) {}

  async findAll() {
    const roles = await this.prisma.role.findMany({
      select: ROLE_SELECT,
      orderBy: { name: 'asc' },
    });
    return roles.map(this.present);
  }

  async getExisting(id: string) {
    const role = await this.prisma.role.findUnique({ where: { id }, select: ROLE_SELECT });
    if (!role) throw new NotFoundException(`Role ${id} not found`);
    return this.present(role);
  }

  async findOne(id: string) {
    return this.getExisting(id);
  }

  async create(dto: CreateRoleDto) {
    const existing = await this.prisma.role.findUnique({ where: { name: dto.name } });
    if (existing) throw new ConflictException('A role with this name already exists');

    const role = await this.prisma.role.create({
      data: { name: dto.name, description: dto.description },
      select: ROLE_SELECT,
    });
    return this.present(role);
  }

  async update(id: string, dto: UpdateRoleDto) {
    const existing = await this.prisma.role.findUnique({ where: { id } });
    if (!existing) throw new NotFoundException(`Role ${id} not found`);
    if (existing.isSystem && dto.name) {
      throw new ConflictException('Cannot rename a system role');
    }

    const role = await this.prisma.role.update({
      where: { id },
      data: { name: dto.name, description: dto.description },
      select: ROLE_SELECT,
    });
    return this.present(role);
  }

  async remove(id: string) {
    const existing = await this.prisma.role.findUnique({
      where: { id },
      include: { _count: { select: { userRoles: true } } },
    });
    if (!existing) throw new NotFoundException(`Role ${id} not found`);
    if (existing.isSystem) throw new ConflictException('Cannot delete a system role');
    if (existing._count.userRoles > 0) {
      throw new ConflictException('Cannot delete a role that is still assigned to users');
    }

    await this.prisma.role.delete({ where: { id } });
    return { id, deleted: true };
  }

  async assignPermissions(id: string, dto: AssignPermissionsDto) {
    await this.getExisting(id);

    const role = await this.prisma.$transaction(async (tx) => {
      await tx.rolePermission.deleteMany({ where: { roleId: id } });
      await tx.rolePermission.createMany({
        data: dto.permissionIds.map((permissionId) => ({ roleId: id, permissionId })),
      });
      return tx.role.findUniqueOrThrow({ where: { id }, select: ROLE_SELECT });
    });

    return this.present(role);
  }

  private present(role: {
    id: string;
    name: string;
    description: string | null;
    isSystem: boolean;
    createdAt: Date;
    updatedAt: Date;
    rolePermissions: {
      permission: { id: string; key: string; description: string | null; module: string | null };
    }[];
  }) {
    const { rolePermissions, ...rest } = role;
    return { ...rest, permissions: rolePermissions.map((rp) => rp.permission) };
  }
}
