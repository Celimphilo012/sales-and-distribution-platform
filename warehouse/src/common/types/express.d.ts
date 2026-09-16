import { AuthenticatedUser } from '../decorators/current-user.decorator';

export interface AuthenticatedApiKey {
  id: string;
  name: string;
  scopes: string[];
}

declare global {
  namespace Express {
    interface Request {
      user?: AuthenticatedUser;
      apiKey?: AuthenticatedApiKey;
      auditEntity?: string;
      auditEntityId?: string;
      auditOldValue?: unknown;
      auditAction?: string;
    }
  }
}

export {};
