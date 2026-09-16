import { SetMetadata } from '@nestjs/common';

export const SCOPES_KEY = 'requiredScopes';

/** The full, fixed set of scopes an API key can hold. */
export const API_KEY_SCOPES = ['catalogue:read', 'stock:read', 'stock:reserve', 'stock:issue'] as const;

export type ApiKeyScope = (typeof API_KEY_SCOPES)[number];

/**
 * Declares the scope(s) an API key must hold to hit this route. Resolved at
 * runtime from the key's own `scopes` column by [ApiKeyGuard] — the
 * API-key parallel to `@RequirePermissions` for JWT users.
 */
export const RequireScopes = (...scopes: ApiKeyScope[]) => SetMetadata(SCOPES_KEY, scopes);
