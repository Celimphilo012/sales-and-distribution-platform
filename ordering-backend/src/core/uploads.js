'use strict';

const { randomUUID } = require('crypto');
const fs = require('fs');
const path = require('path');
const multer = require('multer');
const { badRequest, notFound } = require('./errors');
const { HANDLED } = require('./http');

// Local disk for now (see CLAUDE.md: the file-storage decision — local disk vs a cloud bucket —
// hasn't been made). Nothing outside this file knows where a file physically lives: callers deal
// only with the stored filename the DB keeps and the GET .../file endpoint that serves it, so
// moving to a bucket later means changing this file, not the API shape.
// Anchored to the app folder (not process.cwd()) so it is the same wherever the process starts.
const UPLOAD_ROOT = process.env.UPLOAD_DIR || path.join(__dirname, '..', '..', 'uploads');

const ALLOWED_MIME_TO_EXT = { 'image/jpeg': '.jpg', 'image/png': '.png', 'image/webp': '.webp' };
const EXT_TO_CONTENT_TYPE = {
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.webp': 'image/webp',
};

const IMAGE_MAX_BYTES = 8 * 1024 * 1024; // comfortably fits a real phone photo

const uploadDirFor = (subdir) => path.join(UPLOAD_ROOT, subdir);
const imageFilePath = (subdir, storedFilename) => path.join(uploadDirFor(subdir), storedFilename);
const imageContentType = (storedFilename) =>
  EXT_TO_CONTENT_TYPE[path.extname(storedFilename).toLowerCase()] ?? 'application/octet-stream';

/**
 * Parses a multipart/form-data request with ONE file field into memory (multer): afterwards
 * req.file is the file (or undefined) and req.body holds the plain-text form fields. A file under
 * any other field name, a second file, or a file over `maxBytes` is rejected with a 400.
 */
function readMultipart(req, res, { fieldName, maxBytes }) {
  const middleware = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: maxBytes, files: 1, fields: 20 },
  }).single(fieldName);
  return new Promise((resolve, reject) => middleware(req, res, (error) => (error ? reject(error) : resolve())));
}

/**
 * Saves the request's image part to `uploads/<subdir>/` under a random name (the client's own
 * filename is never used as a path component), rejecting anything that is not a JPEG/PNG/WebP
 * image and anything over IMAGE_MAX_BYTES. Returns { filename, fields } where `fields` holds the
 * plain-text form fields.
 * options: { fieldName = 'file', required = true, invalidTypeMessage }
 */
async function saveImageUpload(req, res, subdir, options = {}) {
  const { fieldName = 'file', required = true, invalidTypeMessage = 'Image must be a JPEG, PNG, or WebP file' } = options;

  await readMultipart(req, res, { fieldName, maxBytes: IMAGE_MAX_BYTES });
  const fields = { ...(req.body ?? {}) };
  const file = req.file;

  if (!file) {
    if (required) throw badRequest('A file is required');
    return { filename: undefined, fields };
  }

  const ext = ALLOWED_MIME_TO_EXT[file.mimetype];
  if (!ext) throw badRequest(invalidTypeMessage);

  await fs.promises.mkdir(uploadDirFor(subdir), { recursive: true });
  const filename = `${randomUUID()}${ext}`;
  await fs.promises.writeFile(imageFilePath(subdir, filename), file.buffer);
  return { filename, fields };
}

/**
 * Best-effort delete of a previously stored file — swallows errors (the DB row is the source of
 * truth; a leftover orphaned file is a disk-space nit, never worth failing a request over).
 */
function deleteImageFile(subdir, storedFilename) {
  fs.promises.unlink(imageFilePath(subdir, storedFilename)).catch(() => {});
}

/**
 * Serves a stored image. The stored filename is random and unique per upload, so it doubles as a
 * perfect ETag: clients revalidate (`no-cache`) and get a cheap 304 instead of re-downloading the
 * bytes on every screen render.
 */
async function sendImageFile(req, res, subdir, storedFilename) {
  const fullPath = imageFilePath(subdir, storedFilename);
  let stat;
  try {
    stat = await fs.promises.stat(fullPath);
  } catch {
    throw notFound('Image file not found');
  }

  const etag = `"${storedFilename}"`;
  res.set({ ETag: etag, 'Cache-Control': 'private, no-cache', 'Last-Modified': stat.mtime.toUTCString() });

  if (req.headers['if-none-match'] === etag) {
    res.status(304).end();
    return HANDLED;
  }

  res.status(200).type(imageContentType(storedFilename)).set('Content-Length', String(stat.size));
  fs.createReadStream(fullPath).pipe(res);
  return HANDLED;
}

module.exports = {
  IMAGE_MAX_BYTES,
  UPLOAD_ROOT,
  readMultipart,
  saveImageUpload,
  deleteImageFile,
  sendImageFile,
  imageFilePath,
  imageContentType,
};
