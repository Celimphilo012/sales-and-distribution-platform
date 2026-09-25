"use strict";
exports.ProductImportSessionStore = void 0;
const crypto_1 = require("crypto");
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
class ProductImportSessionStore {
    constructor() {
        this.sessions = new Map();
    }
    create(createdBy, fileName, toCreate, toUpdate) {
        this.sweepExpired();
        const now = new Date();
        const session = {
            id: (0, crypto_1.randomUUID)(),
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
    take(id) {
        this.sweepExpired();
        const session = this.sessions.get(id);
        if (!session)
            return null;
        if (session.expiresAt.getTime() < Date.now()) {
            this.sessions.delete(id);
            return null;
        }
        return session;
    }
    /** Confirm always consumes the session (success or partial failure) — it's single-use, matching "preview before it counts" (re-uploading gets a fresh preview against current data). */
    discard(id) {
        this.sessions.delete(id);
    }
    sweepExpired() {
        const now = Date.now();
        for (const [id, session] of this.sessions) {
            if (session.expiresAt.getTime() < now)
                this.sessions.delete(id);
        }
    }
}
exports.ProductImportSessionStore = ProductImportSessionStore;
