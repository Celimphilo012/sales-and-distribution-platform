'use strict';

const { randomUUID } = require('crypto');
const fs = require('fs');
const path = require('path');
const { pipeline } = require('stream/promises');
const { badRequest, notFound } = require('./errors');

// Local disk for now (see CLAUDE.md: the file-storage decision — local disk vs a cloud bucket —
// hasn't been made). Nothing outside this file knows where a file physically lives: callers deal
// only with the stored filename the DB keeps and the GET .../file endpoint that serves it, so
// moving to a bucket later means changing this file, not the API shape.
const UPLOAD_ROOT = path.join(process.cwd(), 'uploads');

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
 * Streams the request's `file` part to `uploads/<subdir>/` under a random name (the client's own
 * filename is never used as a path component), rejecting anything that is not a JPEG/PNG/WebP
 * image and anything over IMAGE_MAX_BYTES. Returns { filename, fields } where `fields` holds the
 * plain-text form fields, whether they arrived before or after the file.
 * options: { fieldName = 'file', required = true, invalidTypeMessage }
 */
async function saveImageUpload(request, subdir, options = {}) {
  const { fieldName = 'file', required = true, invalidTypeMessage = 'Image must be a JPEG, PNG, or WebP file' } = options;
  const fields = {};
  let filename;

  for await (const part of request.parts({ limits: { fileSize: IMAGE_MAX_BYTES } })) {
    if (part.type !== 'file') {
      fields[part.fieldname] = part.value;
      continue;
    }

    if (part.fieldname !== fieldName || filename) {
      part.file.resume();
      throw badRequest(`Upload rejected: Unexpected field "${part.fieldname}"`);
    }

    const ext = ALLOWED_MIME_TO_EXT[part.mimetype];
    if (!ext) {
      part.file.resume();
      throw badRequest(invalidTypeMessage);
    }

    await fs.promises.mkdir(uploadDirFor(subdir), { recursive: true });
    const stored = `${randomUUID()}${ext}`;
    const target = imageFilePath(subdir, stored);

    try {
      await pipeline(part.file, fs.createWriteStream(target));
      if (part.file.truncated) {
        throw Object.assign(new Error('File is too large.'), { code: 'FST_REQ_FILE_TOO_LARGE' });
      }
    } catch (error) {
      await fs.promises.unlink(target).catch(() => {});
      throw error;
    }
    filename = stored;
  }

  if (!filename && required) throw badRequest('A file is required');
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
async function sendImageFile(request, reply, subdir, storedFilename) {
  const fullPath = imageFilePath(subdir, storedFilename);
  let stat;
  try {
    stat = await fs.promises.stat(fullPath);
  } catch {
    throw notFound('Image file not found');
  }

  const etag = `"${storedFilename}"`;
  reply.header('ETag', etag).header('Cache-Control', 'private, no-cache').header('Last-Modified', stat.mtime.toUTCString());

  if (request.headers['if-none-match'] === etag) return reply.code(304).send();

  return reply
    .type(imageContentType(storedFilename))
    .header('Content-Length', stat.size)
    .send(fs.createReadStream(fullPath));
}

module.exports = { IMAGE_MAX_BYTES, saveImageUpload, deleteImageFile, sendImageFile, imageFilePath, imageContentType };
