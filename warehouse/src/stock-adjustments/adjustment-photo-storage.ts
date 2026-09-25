import { randomUUID } from 'crypto';
import { existsSync, mkdirSync } from 'fs';
import { extname, join } from 'path';
import { BadRequestException } from '@nestjs/common';
import { diskStorage } from 'multer';
import type { Options as MulterOptions } from 'multer';

// Local disk for now (see CLAUDE.md: the platform's broader file-storage
// decision — local disk vs. a cloud bucket — hasn't been made yet). Nothing
// outside this file knows or cares where a photo physically lives: callers
// only ever deal with the `photoPath` filename the DB stores and the
// GET .../photo endpoint that serves it, so swapping to a bucket later means
// changing this file, not the API shape.
export const ADJUSTMENT_PHOTO_UPLOAD_DIR = join(process.cwd(), 'uploads', 'adjustments');

const ALLOWED_MIME_TO_EXT: Record<string, string> = {
  'image/jpeg': '.jpg',
  'image/png': '.png',
  'image/webp': '.webp',
};

export const ADJUSTMENT_PHOTO_MAX_BYTES = 8 * 1024 * 1024; // 8MB — a real phone camera photo comfortably fits.

function ensureUploadDirExists() {
  if (!existsSync(ADJUSTMENT_PHOTO_UPLOAD_DIR)) {
    mkdirSync(ADJUSTMENT_PHOTO_UPLOAD_DIR, { recursive: true });
  }
}

/**
 * Multer config for the adjustment-photo upload field: writes straight to
 * disk under a randomly generated name (never the client's own filename —
 * that's never trusted as a path component), rejects anything that isn't a
 * JPEG/PNG/WebP image, and caps size before the body is even fully read.
 */
export const adjustmentPhotoMulterOptions: MulterOptions = {
  storage: diskStorage({
    destination: (_req, _file, callback) => {
      ensureUploadDirExists();
      callback(null, ADJUSTMENT_PHOTO_UPLOAD_DIR);
    },
    filename: (_req, file, callback) => {
      const ext = ALLOWED_MIME_TO_EXT[file.mimetype] ?? extname(file.originalname) ?? '';
      callback(null, `${randomUUID()}${ext}`);
    },
  }),
  limits: { fileSize: ADJUSTMENT_PHOTO_MAX_BYTES },
  fileFilter: (_req, file, callback) => {
    if (!ALLOWED_MIME_TO_EXT[file.mimetype]) {
      // multer's FileFilterCallback type only accepts a single arg for the
      // error case (its second overload is `(error: null, acceptFile)`).
      callback(new BadRequestException('Photo must be a JPEG, PNG, or WebP image'));
      return;
    }
    callback(null, true);
  },
};

/** Resolves a stored `photoPath` (just a filename) to its full location on disk. */
export function adjustmentPhotoFilePath(photoPath: string): string {
  return join(ADJUSTMENT_PHOTO_UPLOAD_DIR, photoPath);
}

const EXT_TO_CONTENT_TYPE: Record<string, string> = {
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.webp': 'image/webp',
};

/** Content-Type to serve a stored photo with, derived from its own extension. */
export function adjustmentPhotoContentType(photoPath: string): string {
  return EXT_TO_CONTENT_TYPE[extname(photoPath).toLowerCase()] ?? 'application/octet-stream';
}
