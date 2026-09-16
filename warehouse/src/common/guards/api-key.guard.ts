import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import * as argon2 from 'argon2';
import { Request } from 'express';
import { PrismaService } from '../prisma/prisma.service';
import { SCOPES_KEY } from '../decorators/require-scopes.decorator';

const API_KEY_HEADER = 'x-api-key';

/**
 * Authenticates system-to-system callers via the `X-API-Key` header —
 * the external-API parallel to `AuthGuard` (JWT) + `PermissionGuard`
 * combined into one guard, since a key's scopes are checked the same way a
 * user's permissions are.
 *
 * Keys are stored only as an argon2 hash (never the raw value), which is a
 * salted, non-deterministic hash — there is no `WHERE key_hash = ?` lookup
 * possible. Instead this verifies the presented key against every ACTIVE
 * key's hash, exactly like a password check. That is O(active keys) per
 * request, which is fine for "minimal mechanism, no management UI" (a
 * handful of integration partners) — it would need a public lookup prefix
 * (GitHub/Stripe-style) to scale past that.
 */
@Injectable()
export class ApiKeyGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly prisma: PrismaService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const required = this.reflector.getAllAndOverride<string[]>(SCOPES_KEY, [
      context.getHandler(),
      context.getClass(),
    ]) ?? [];

    const request = context.switchToHttp().getRequest<Request>();
    const rawKey = request.headers[API_KEY_HEADER];
    if (!rawKey || typeof rawKey !== 'string') {
      throw new UnauthorizedException('Missing API key');
    }

    const candidates = await this.prisma.apiKey.findMany({ where: { isActive: true } });
    let matched: (typeof candidates)[number] | undefined;
    for (const candidate of candidates) {
      if (await argon2.verify(candidate.keyHash, rawKey)) {
        matched = candidate;
        break;
      }
    }
    if (!matched) {
      throw new UnauthorizedException('Invalid or inactive API key');
    }

    const scopes = matched.scopes as string[];
    const hasAll = required.every((scope) => scopes.includes(scope));
    if (!hasAll) {
      throw new ForbiddenException('API key lacks the required scope');
    }

    request.apiKey = { id: matched.id, name: matched.name, scopes };

    // Fire-and-forget: must never slow down or fail the guarded request.
    void this.prisma.apiKey
      .update({ where: { id: matched.id }, data: { lastUsedAt: new Date() } })
      .catch(() => {});

    return true;
  }
}
