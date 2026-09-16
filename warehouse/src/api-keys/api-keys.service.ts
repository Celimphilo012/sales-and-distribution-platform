import { Injectable, NotFoundException } from '@nestjs/common';
import { randomBytes } from 'crypto';
import * as argon2 from 'argon2';
import { PrismaService } from '../common/prisma/prisma.service';
import { CreateApiKeyDto } from './dto/create-api-key.dto';

const KEY_SELECT = {
  id: true,
  name: true,
  scopes: true,
  isActive: true,
  createdAt: true,
  lastUsedAt: true,
  createdBy: true,
} as const;

@Injectable()
export class ApiKeysService {
  constructor(private readonly prisma: PrismaService) {}

  findAll() {
    return this.prisma.apiKey.findMany({ select: KEY_SELECT, orderBy: { createdAt: 'asc' } });
  }

  async getExisting(id: string) {
    const key = await this.prisma.apiKey.findUnique({ where: { id }, select: KEY_SELECT });
    if (!key) throw new NotFoundException(`API key ${id} not found`);
    return key;
  }

  /**
   * The raw key is generated here, hashed with argon2 (same as a password),
   * and only the hash is ever persisted — this is the ONE moment the raw
   * value exists outside the caller's own storage. The response includes it
   * once; it can never be retrieved again after this call returns.
   */
  async create(dto: CreateApiKeyDto, createdBy: string) {
    const rawKey = `whk_${randomBytes(32).toString('base64url')}`;
    const keyHash = await argon2.hash(rawKey);

    const created = await this.prisma.apiKey.create({
      data: { name: dto.name, keyHash, scopes: dto.scopes, createdBy },
      select: KEY_SELECT,
    });

    return { ...created, rawKey };
  }

  async revoke(id: string) {
    await this.getExisting(id);
    return this.prisma.apiKey.update({ where: { id }, data: { isActive: false }, select: KEY_SELECT });
  }
}
