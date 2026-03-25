const { S3Client, PutObjectCommand, DeleteObjectCommand, ListObjectsV2Command } = require('@aws-sdk/client-s3');
const mongoose = require('mongoose');
require('dotenv').config();

/**
 * Digital Ocean Spaces - HRMS folder structure (see project docs):
 * {baseFolder}/{companyName}/
 *   attendance/{employeeName}/{YYYY-MM}/     punch_in|punch_out_{timestamp}_{id}.jpg
 *   employees/{employeeName}/documents/onboarding|reimbursements|tasks-proof|other/, avatar/, payslips/
 *   candidates/{candidateName}/documents/..., avatar/
 *   company/logos|policies|documents|assets/
 *   courses/{courseName}/videos|documents|thumbnails|attachments/
 *   assets/images|icons|files/
 *   announcements/{announcementId}/
 *   documents/general/
 * baseFolder: ekta-dev (hrms.askeva.net, localhost) | ekta-production (my.ektahr.com)
 */
// Digital Ocean Spaces configuration from environment variables
const DIGITAL_OCEAN_ACCESS_KEY = process.env.DIGITAL_OCEAN_ACCESS_KEY;
const DIGITAL_OCEAN_SECRET_KEY = process.env.DIGITAL_OCEAN_SECRET_KEY;
const DIGITAL_OCEAN_REGION = process.env.DIGITAL_OCEAN_REGION || 'blr1';
const DIGITAL_OCEAN_ENDPOINT = process.env.DIGITAL_OCEAN_ENDPOINT || `https://${process.env.DIGITAL_OCEAN_REGION || 'blr1'}.digitaloceanspaces.com`;
const BUCKET_NAME = process.env.DIGITAL_OCEAN_BUCKET_NAME || 'hrms-storage';
/** When false, upload without object ACL (required if bucket has "ACLs disabled"). */
const USE_OBJECT_ACL = process.env.DIGITAL_OCEAN_USE_OBJECT_ACL !== '0'
  && process.env.DIGITAL_OCEAN_USE_OBJECT_ACL !== 'false';

function shouldRetryUploadWithoutAcl(err) {
  const msg = String(err?.message || err?.Code || '').toLowerCase();
  const name = String(err?.name || '');
  return name === 'AccessControlListNotSupported'
    || msg.includes('acl')
    || msg.includes('does not allow')
    || msg.includes('bucketownerforced')
    || msg.includes('access control list');
}

// Validate required environment variables
if (!DIGITAL_OCEAN_ACCESS_KEY || !DIGITAL_OCEAN_SECRET_KEY) {
  console.error('[DigitalOceanService] ⚠️  WARNING: Digital Ocean credentials not configured in environment variables!');
  console.error('[DigitalOceanService] Please set the following in your .env file:');
  console.error('[DigitalOceanService]   - DIGITAL_OCEAN_ACCESS_KEY');
  console.error('[DigitalOceanService]   - DIGITAL_OCEAN_SECRET_KEY');
  console.error('[DigitalOceanService]   - DIGITAL_OCEAN_REGION (optional, default: blr1)');
  console.error('[DigitalOceanService]   - DIGITAL_OCEAN_ENDPOINT (optional, auto-generated)');
  console.error('[DigitalOceanService]   - DIGITAL_OCEAN_BUCKET_NAME (optional, default: hrms-storage)');
}

let s3Client = null;
if (DIGITAL_OCEAN_ACCESS_KEY && DIGITAL_OCEAN_SECRET_KEY) {
  s3Client = new S3Client({
    endpoint: DIGITAL_OCEAN_ENDPOINT,
    forcePathStyle: false,
    region: DIGITAL_OCEAN_REGION,
    credentials: {
      accessKeyId: DIGITAL_OCEAN_ACCESS_KEY,
      secretAccessKey: DIGITAL_OCEAN_SECRET_KEY,
    },
  });
  console.log('[DigitalOceanService] ✅ Digital Ocean Spaces client initialized');
} else {
  console.error('[DigitalOceanService] ❌ Digital Ocean Spaces client NOT initialized - missing credentials');
}

/**
 * Determine the base folder based on the request origin/hostname
 * - hrms.askeva.net or localhost -> "ekta-dev"
 * - my.ektahr.com -> "ekta-production"
 */
function getBaseFolder(req) {
  if (!req) return 'ekta-dev';
  const origin = req.headers.origin || req.headers.host || '';
  const hostname = origin.replace(/^https?:\/\//, '').split(':')[0].toLowerCase();
  if (hostname === 'my.ektahr.com') return 'ekta-production';
  if (hostname === 'hrms.askeva.net' || hostname === 'localhost' || hostname === '127.0.0.1') return 'ekta-dev';
  return 'ekta-dev';
}

function sanitizeName(name) {
  return String(name)
    .replace(/[^a-zA-Z0-9._-]/g, '_')
    .replace(/_{2,}/g, '_')
    .replace(/^_+|_+$/g, '')
    .toLowerCase();
}

function generateSecureFileName(prefix, extension = 'jpg') {
  const timestamp = Date.now();
  const randomId = Math.round(Math.random() * 1e12).toString(36);
  const safeExt = extension.startsWith('.') ? extension.slice(1) : extension;
  return `${prefix}_${timestamp}_${randomId}.${safeExt}`;
}

async function getCompanyName(companyId) {
  if (!companyId || !mongoose.Types.ObjectId.isValid(companyId)) return 'unknown';
  try {
    const Company = require('../models/Company');
    const company = await Company.findById(companyId).select('name').lean();
    if (company && company.name) return company.name;
  } catch (err) {
    console.error('[DigitalOceanService] Error fetching company name:', err);
  }
  return 'unknown';
}

// Categories per Digital Ocean Spaces folder structure doc
const CATEGORIES = ['company', 'employees', 'candidates', 'courses', 'attendance', 'assets', 'announcements', 'documents'];

/**
 * Build folder path per HRMS structure: {baseFolder}/{companyName}/{category}/{entityName?}/{subfolder?}
 * - attendance: entityName=employeeName, subfolder=YYYY-MM
 * - employees: entityName=employeeName, subfolder=e.g. documents/onboarding, avatar, payslips
 * - candidates: entityName=candidateName, subfolder=e.g. documents/resumes
 * - company: no entityName, subfolder=e.g. logos, policies
 * - courses: entityName=courseName, subfolder=e.g. videos, documents
 * - assets: no entityName, subfolder=e.g. images, icons
 * - announcements: no entityName, subfolder=announcementId
 * - documents: no entityName, subfolder=e.g. general
 */
function sanitizeSubfolder(subfolder) {
  if (!subfolder || typeof subfolder !== 'string') return '';
  return subfolder.split('/').map(part => sanitizeName(part)).filter(Boolean).join('/');
}

async function buildFolderPath(req, category, companyId, entityName, subfolder) {
  const baseFolder = getBaseFolder(req);
  const companyName = await getCompanyName(companyId);
  const sanitizedCompanyName = sanitizeName(companyName);
  let path = `${baseFolder}/${sanitizedCompanyName}/${category}`;
  if (entityName) path += `/${sanitizeName(entityName)}`;
  const safeSubfolder = sanitizeSubfolder(subfolder);
  if (safeSubfolder) path += `/${safeSubfolder}`;
  return path;
}

async function uploadBuffer(buffer, options = {}) {
  try {
    if (!s3Client) {
      return { success: false, error: 'Digital Ocean Spaces is not configured. Set DIGITAL_OCEAN_ACCESS_KEY and DIGITAL_OCEAN_SECRET_KEY in .env' };
    }
    const { folder, fileName, contentType = 'application/octet-stream', metadata = {}, req, companyId, employeeName, category = 'documents', subfolder } = options;

    let key;
    if (folder) {
      const secureFileName = fileName || generateSecureFileName('file', 'pdf');
      key = folder.endsWith('/') ? folder + secureFileName : `${folder}/${secureFileName}`;
    } else if (companyId && category) {
      const folderPath = await buildFolderPath(req, category, companyId, employeeName, subfolder);
      const secureFileName = fileName ? sanitizeName(fileName) : generateSecureFileName('file', 'pdf');
      key = `${folderPath}/${secureFileName}`;
    } else {
      const baseFolder = getBaseFolder(req);
      const secureFileName = fileName ? sanitizeName(fileName) : generateSecureFileName('file', 'pdf');
      key = `${baseFolder}/${secureFileName}`;
    }

    const basePut = {
      Bucket: BUCKET_NAME,
      Key: key,
      Body: buffer,
      ContentType: contentType,
      Metadata: metadata,
    };
    try {
      if (USE_OBJECT_ACL) {
        await s3Client.send(new PutObjectCommand({ ...basePut, ACL: 'public-read' }));
      } else {
        await s3Client.send(new PutObjectCommand(basePut));
      }
    } catch (firstErr) {
      if (USE_OBJECT_ACL && shouldRetryUploadWithoutAcl(firstErr)) {
        console.warn('[DigitalOceanService] Retrying upload without object ACL (bucket may disallow ACLs)');
        await s3Client.send(new PutObjectCommand(basePut));
      } else {
        throw firstErr;
      }
    }

    const cdnBase = (process.env.DIGITAL_OCEAN_SPACES_CDN_URL || '').replace(/\/+$/, '');
    const url = cdnBase
      ? `${cdnBase}/${key}`
      : `https://${BUCKET_NAME}.${DIGITAL_OCEAN_REGION}.digitaloceanspaces.com/${key}`;
    return { success: true, url, key };
  } catch (err) {
    console.error('[DigitalOceanService] Upload error:', err);
    return { success: false, error: err.message || 'Failed to upload file' };
  }
}

async function uploadImage(buffer, folder, options = {}) {
  if (typeof folder === 'object' && folder !== null && !options.req) {
    options = folder;
    folder = 'hrms/images';
  } else if (typeof folder !== 'string') {
    folder = 'hrms/images';
  }
  let contentType = 'image/jpeg';
  if (options.format) {
    contentType = `image/${options.format}`;
  } else {
    if (buffer[0] === 0x89 && buffer[1] === 0x50) contentType = 'image/png';
    else if (buffer[0] === 0xFF && buffer[1] === 0xD8) contentType = 'image/jpeg';
    else if (buffer[0] === 0x47 && buffer[1] === 0x49) contentType = 'image/gif';
  }
  const ext = options.format || 'jpg';
  const fileName = options.fileName || generateSecureFileName('img', ext);
  return uploadBuffer(buffer, {
    folder: options.category ? undefined : folder,
    fileName,
    contentType,
    req: options.req,
    companyId: options.companyId,
    employeeName: options.employeeName,
    category: options.category || 'documents',
    subfolder: options.subfolder,
  });
}

async function uploadDocument(buffer, folder, originalFilename, options = {}) {
  if (typeof folder === 'object' && folder !== null) {
    options = folder;
    folder = 'hrms/documents';
    originalFilename = undefined;
  } else if (typeof originalFilename === 'object' && originalFilename !== null) {
    options = originalFilename;
    originalFilename = undefined;
  }
  folder = folder || 'hrms/documents';
  let prefix = options.filePrefix != null ? String(options.filePrefix) : null;
  let fileExt = '.pdf';
  if (originalFilename) {
    const extMatch = originalFilename.match(/\.[a-zA-Z0-9]+$/);
    if (extMatch) fileExt = extMatch[0].toLowerCase();
    if (prefix == null) {
      const nameWithoutExt = originalFilename.replace(/\.[a-zA-Z0-9]+$/, '');
      const prefixMatch = nameWithoutExt.match(/^([^_]+)/);
      prefix = prefixMatch && prefixMatch[1].length <= 20 ? sanitizeName(prefixMatch[1].substring(0, 20)) : 'doc';
    }
  }
  if (prefix == null) prefix = 'doc';
  const fileSafeExt = fileExt.startsWith('.') ? fileExt.slice(1) : fileExt;
  const fileName = options.fileName ? sanitizeName(options.fileName) : generateSecureFileName(prefix, fileSafeExt);
  const contentTypeExt = fileName.match(/\.[a-zA-Z0-9]+$/)?.[0]?.toLowerCase() || '.pdf';
  const contentTypeSafeExt = contentTypeExt.startsWith('.') ? contentTypeExt.slice(1) : contentTypeExt;
  const contentType = options.contentType ||
    (contentTypeSafeExt === 'pdf' ? 'application/pdf' :
      contentTypeSafeExt === 'doc' ? 'application/msword' :
        contentTypeSafeExt === 'docx' ? 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' :
          contentTypeSafeExt === 'jpg' || contentTypeSafeExt === 'jpeg' ? 'image/jpeg' :
            contentTypeSafeExt === 'png' ? 'image/png' : 'application/octet-stream');

  return uploadBuffer(buffer, {
    folder: options.category ? undefined : folder,
    fileName,
    contentType,
    req: options.req,
    companyId: options.companyId,
    employeeName: options.employeeName,
    category: options.category || 'documents',
    subfolder: options.subfolder,
  });
}

/**
 * Upload onboarding document to employees/{employeeName}/documents/onboarding/
 * Naming: onboarding_{onboardingId}_{documentId}_{timestamp}.{ext}
 */
async function uploadOnboardingDocument(buffer, req, companyId, employeeName, onboardingId, documentId, fileExt) {
  const ext = (fileExt && fileExt.startsWith('.')) ? fileExt.slice(1) : (fileExt || 'pdf');
  const safeExt = /^[a-z0-9]+$/i.test(ext) ? ext : 'pdf';
  const fileName = `onboarding_${onboardingId}_${documentId}_${Date.now()}.${safeExt}`;
  return uploadDocument(buffer, undefined, `file.${safeExt}`, {
    req,
    companyId,
    employeeName,
    category: 'employees',
    subfolder: 'documents/onboarding',
    fileName,
  });
}

async function deleteFile(key) {
  try {
    if (!s3Client) return { success: false, error: 'Digital Ocean Spaces is not configured' };
    await s3Client.send(new DeleteObjectCommand({ Bucket: BUCKET_NAME, Key: key }));
    return { success: true };
  } catch (err) {
    console.error('[DigitalOceanService] Delete error:', err);
    return { success: false, error: err.message || 'Failed to delete file' };
  }
}

function extractKey(url) {
  try {
    const match = url.match(/https?:\/\/[^/]+\/(.+)$/);
    if (match && match[1]) return decodeURIComponent(match[1]);
  } catch (_) {}
  return null;
}

async function deleteFileByUrl(url) {
  const key = extractKey(url);
  if (!key) return { success: false, error: 'Could not extract key from URL' };
  return deleteFile(key);
}

async function listFiles(prefix) {
  try {
    if (!s3Client) return [];
    const response = await s3Client.send(new ListObjectsV2Command({ Bucket: BUCKET_NAME, Prefix: prefix }));
    return (response.Contents || []).map(obj => obj.Key || '').filter(Boolean);
  } catch (err) {
    console.error('[DigitalOceanService] List files error:', err);
    return [];
  }
}

async function cleanupOldAttendanceImages(req, companyId, employeeName) {
  try {
    const baseFolder = getBaseFolder(req);
    const companyName = await getCompanyName(companyId);
    const sanitizedCompanyName = sanitizeName(companyName);
    const sanitizedEmployeeName = sanitizeName(employeeName);
    const prefix = `${baseFolder}/${sanitizedCompanyName}/attendance/${sanitizedEmployeeName}/`;
    const now = new Date();
    const currentYear = now.getFullYear();
    const currentMonth = now.getMonth() + 1;
    const monthsToKeep = [];
    for (let i = 0; i < 3; i++) {
      const date = new Date(currentYear, currentMonth - 1 - i, 1);
      const year = date.getFullYear();
      const month = String(date.getMonth() + 1).padStart(2, '0');
      monthsToKeep.push(`${year}-${month}`);
    }
    const allFiles = await listFiles(prefix);
    let deleted = 0;
    let errors = 0;
    for (const fileKey of allFiles) {
      const pathParts = fileKey.split('/');
      const monthIndex = pathParts.findIndex(part => /^\d{4}-\d{2}$/.test(part));
      if (monthIndex !== -1 && !monthsToKeep.includes(pathParts[monthIndex])) {
        const result = await deleteFile(fileKey);
        if (result.success) deleted++;
        else errors++;
      }
    }
    if (deleted > 0) console.log(`[DigitalOceanService] Cleanup: ${deleted} files deleted, ${errors} errors`);
    return { deleted, errors };
  } catch (err) {
    console.error('[DigitalOceanService] Cleanup error:', err);
    return { deleted: 0, errors: 1 };
  }
}

async function uploadAttendanceImage(buffer, req, companyId, employeeName, type, options = {}) {
  try {
    const now = new Date();
    const year = now.getFullYear();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const monthFolder = `${year}-${month}`;
    const fileName = generateSecureFileName(type.replace('-', '_'), 'jpg');
    const result = await uploadImage(buffer, undefined, {
      req,
      companyId,
      employeeName,
      category: 'attendance',
      subfolder: monthFolder,
      fileName,
      format: 'jpg',
      ...options,
    });
    cleanupOldAttendanceImages(req, companyId, employeeName).catch(err => console.error('[DigitalOceanService] Background cleanup error:', err));
    return result;
  } catch (err) {
    console.error('[DigitalOceanService] Upload attendance image error:', err);
    return { success: false, error: err.message || 'Failed to upload attendance image' };
  }
}

module.exports = {
  uploadBuffer,
  uploadImage,
  uploadDocument,
  deleteFile,
  deleteFileByUrl,
  extractKey,
  listFiles,
  cleanupOldAttendanceImages,
  uploadAttendanceImage,
  uploadOnboardingDocument,
  getBaseFolder,
  getCompanyName,
  sanitizeName,
  generateSecureFileName,
  buildFolderPath,
  sanitizeSubfolder,
};
