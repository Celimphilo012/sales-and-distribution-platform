import { SetMetadata } from '@nestjs/common';

export const SCOPES_KEY = 'requiredScopes';

/**
 * The full, fixed set of scopes an API key can hold. `locations:read` (STEP
 * R3b) lets the back-office relay the leaf-location list to the ordering
 * frontend, so a manager reserving an order's stock can pick a real
 * location instead of the reserve endpoint having nothing to offer one
 * from — the same scoped-key model ARCHITECTURE.md §A2 already describes,
 * just one more scope in it.
 */
export const API_KEY_SCOPES = ['catalogue:read', 'stock:read', 'stock:reserve', 'stock:issue', 'locations:read'] as const;

export type ApiKeyScope = (typeof API_KEY_SCOPES)[number];

/**
 * Declares the scope(s) an API key must hold to hit this route. Resolved at
 * runtime from the key's own `scopes` column by [ApiKeyGuard] — the
 * API-key parallel to `@RequirePermissions` for JWT users.
 */
export const RequireScopes = (...scopes: ApiKeyScope[]) => SetMetadata(SCOPES_KEY, scopes);
