import { PrismaService } from '../prisma/prisma.service';

/**
 * Resolves a user's effective permission keys via
 * user_roles -> roles -> role_permissions -> permissions, deduped.
 *
 * This is the single source of truth for "what can this user do" — both
 * `PermissionGuard` (enforcement) and `GET /auth/me` (what the client is
 * told) call this exact function, so they can never disagree.
 */
export async function resolveEffectivePermissionKeys(
  prisma: PrismaService,
  userId: string,
): Promise<string[]> {
  const grants = await prisma.rolePermission.findMany({
    where: { role: { userRoles: { some: { userId } } } },
    select: { permission: { select: { key: true } } },
  });
  return [...new Set(grants.map((g) => g.permission.key))];
}
