import {
  CallHandler,
  ExecutionContext,
  Injectable,
  NestInterceptor,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { Request } from 'express';
import { Observable } from 'rxjs';
import { tap } from 'rxjs/operators';
import { PrismaService } from '../prisma/prisma.service';

const MUTATING_METHODS = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);

const METHOD_ACTIONS: Record<string, string> = {
  POST: 'CREATE',
  PUT: 'UPDATE',
  PATCH: 'UPDATE',
  DELETE: 'DELETE',
};

const SENSITIVE_KEYS = new Set([
  'password',
  'passwordHash',
  'currentPassword',
  'newPassword',
  'refreshToken',
  'accessToken',
  'token',
]);

function redact(body: unknown): Record<string, unknown> | undefined {
  if (!body || typeof body !== 'object') return undefined;
  const entries = Object.entries(body as Record<string, unknown>).map(([key, value]) =>
    SENSITIVE_KEYS.has(key) ? [key, '[REDACTED]'] : [key, value],
  );
  return Object.fromEntries(entries);
}

/**
 * Writes one audit_logs row for every mutating request that completes
 * successfully. Entity name defaults to the first URL segment (e.g.
 * "users", "roles") and entity id to the most specific route param (e.g.
 * "imageId" on a nested /products/:id/images/:imageId route). Controllers
 * may set request.auditEntity / request.auditEntityId / request.auditOldValue
 * / request.auditAction before the handler returns to override any of
 * these — needed for nested resources (product images) and non-CRUD
 * actions (login) — but nothing is required for the common CRUD case.
 */
@Injectable()
export class AuditInterceptor implements NestInterceptor {
  constructor(private readonly prisma: PrismaService) {}

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const request = context.switchToHttp().getRequest<Request>();
    const method = request.method.toUpperCase();

    if (!MUTATING_METHODS.has(method)) {
      return next.handle();
    }

    return next.handle().pipe(
      tap((response) => {
        void this.writeAuditLog(request, method, response);
      }),
    );
  }

  private async writeAuditLog(request: Request, method: string, response: unknown) {
    try {
      const entity = request.auditEntity ?? request.path.split('/').filter(Boolean)[0] ?? 'unknown';
      const routeParamValues = Object.values(request.params ?? {});
      const entityId =
        request.auditEntityId ??
        routeParamValues[routeParamValues.length - 1] ??
        (response as { id?: string } | undefined)?.id ??
        null;

      await this.prisma.auditLog.create({
        data: {
          userId: request.user?.id ?? null,
          action: request.auditAction ?? METHOD_ACTIONS[method] ?? method,
          entity,
          entityId: entityId ?? null,
          oldValue: (request.auditOldValue as Prisma.InputJsonValue | undefined) ?? undefined,
          newValue:
            method === 'DELETE'
              ? undefined
              : (redact(request.body) as Prisma.InputJsonValue | undefined),
        },
      });
    } catch {
      // Audit logging must never break the primary request/response cycle.
    }
  }
}
