import { AuthenticatedUser } from '../decorators/current-user.decorator';

declare global {
  namespace Express {
    interface Request {
      user?: AuthenticatedUser;
      auditEntity?: string;
      auditEntityId?: string;
      auditOldValue?: unknown;
      auditAction?: string;
    }
  }
}

export {};
