import { Injectable } from '@nestjs/common';
import { randomUUID } from 'crypto';
import type { ImportCreateRow, ImportUpdateRow } from './product-import.types';

export interface ImportSession {
  id: string;
  createdBy: string;
  fileName: string;
  createdAt: Date;
  expiresAt: Date;
  toCreate: ImportCreateRow[];
  toUpdate: ImportUpdateRow[];
}

const SESSION_TTL_MS = 15 * 60 * 1000; // "short TTL, keep it simple" — 15 minutes covers "upload, read the preview, confirm" comfortably without lingering.

/**
 * In-memory preview->confirm handoff, per the task's own "keep it simple"
 * option (a temp table would survive a server restart, which nothing else
 * about this feature needs — a lost session on restart just means
 * re-uploading, and the confirm step re-validates everything against the
 * DB anyway). Single-instance only, matching this app's current deployment
 * (one Nest process) — a multi-instance deployment would need a shared
 * store instead (Redis, or an actual temp table).
 */
@Injectable()
export class ProductImportSessionStore {
  private readonly sessions = new Map<string, ImportSession>();

  create(createdBy: string, fileName: string, toCreate: ImportCreateRow[], toUpdate: ImportUpdateRow[]): ImportSession {
    this.sweepExpired();
    const now = new Date();
    const session: ImportSession = {
      id: randomUUID(),
      createdBy,
      fileName,
      createdAt: now,
      expiresAt: new Date(now.getTime() + SESSION_TTL_MS),
      toCreate,
      toUpdate,
    };
    this.sessions.set(session.id, session);
    return session;
  }

  /** Returns the session, or `null` if it never existed or has expired (expired entries are dropped here, not just ignored). */
  take(id: string): ImportSession | null {
    this.sweepExpired();
    const session = this.sessions.get(id);
    if (!session) return null;
    if (session.expiresAt.getTime() < Date.now()) {
      this.sessions.delete(id);
      return null;
    }
    return session;
  }

  /** Confirm always consumes the session (success or partial failure) — it's single-use, matching "preview before it counts" (re-uploading gets a fresh preview against current data). */
  discard(id: string): void {
    this.sessions.delete(id);
  }

  private sweepExpired(): void {
    const now = Date.now();
    for (const [id, session] of this.sessions) {
      if (session.expiresAt.getTime() < now) this.sessions.delete(id);
    }
  }
}
