import {
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import * as argon2 from 'argon2';
import { PrismaService } from '../common/prisma/prisma.service';
import { CreateUserDto } from './dto/create-user.dto';
import { UpdateUserDto } from './dto/update-user.dto';

const USER_SELECT = {
  id: true,
  email: true,
  fullName: true,
  status: true,
  createdAt: true,
  updatedAt: true,
  userRoles: {
    select: { role: { select: { id: true, name: true } } },
  },
} as const;

@Injectable()
export class UsersService {
  constructor(private readonly prisma: PrismaService) {}

  async findAll() {
    const users = await this.prisma.user.findMany({
      select: USER_SELECT,
      orderBy: { createdAt: 'asc' },
    });
    return users.map(this.present);
  }

  async findOne(id: string) {
    const user = await this.prisma.user.findUnique({ where: { id }, select: USER_SELECT });
    if (!user) throw new NotFoundException(`User ${id} not found`);
    return this.present(user);
  }

  async create(dto: CreateUserDto) {
    const existing = await this.prisma.user.findUnique({ where: { email: dto.email } });
    if (existing) throw new ConflictException('A user with this email already exists');

    const passwordHash = await argon2.hash(dto.password);

    const user = await this.prisma.user.create({
      data: {
        email: dto.email,
        passwordHash,
        fullName: dto.fullName,
        userRoles: dto.roleIds
          ? { create: dto.roleIds.map((roleId) => ({ roleId })) }
          : undefined,
      },
      select: USER_SELECT,
    });
    return this.present(user);
  }

  async getExisting(id: string) {
    const user = await this.prisma.user.findUnique({ where: { id }, select: USER_SELECT });
    if (!user) throw new NotFoundException(`User ${id} not found`);
    return this.present(user);
  }

  async update(id: string, dto: UpdateUserDto) {
    await this.getExisting(id);

    const passwordHash = dto.password ? await argon2.hash(dto.password) : undefined;

    const user = await this.prisma.$transaction(async (tx) => {
      if (dto.roleIds) {
        await tx.userRole.deleteMany({ where: { userId: id } });
      }
      return tx.user.update({
        where: { id },
        data: {
          fullName: dto.fullName,
          status: dto.status,
          passwordHash,
          userRoles: dto.roleIds
            ? { create: dto.roleIds.map((roleId) => ({ roleId })) }
            : undefined,
        },
        select: USER_SELECT,
      });
    });

    return this.present(user);
  }

  async remove(id: string) {
    await this.getExisting(id);
    // Users are never hard-deleted; deactivate instead so historical
    // audit_logs / created records keep a valid author reference.
    const user = await this.prisma.user.update({
      where: { id },
      data: { status: 'INACTIVE' },
      select: USER_SELECT,
    });
    return this.present(user);
  }

  private present(user: {
    id: string;
    email: string;
    fullName: string;
    status: string;
    createdAt: Date;
    updatedAt: Date;
    userRoles: { role: { id: string; name: string } }[];
  }) {
    const { userRoles, ...rest } = user;
    return { ...rest, roles: userRoles.map((ur) => ur.role) };
  }
}
