// Shared helper for the rolling face-validation reference used by attendance
// punches, breaks and custom-permission punches.
//
// Each successful selfie capture rolls `Staff.faceReferenceImage` forward to that
// image, so the NEXT capture is validated (via /auth/verify-face) against the most
// recent one. The very first capture also seeds `faceFirstImage` (the 1st taken
// image, kept permanently) and `avatar` (profile photo) when those are empty.
const Staff = require('../models/Staff');
const digitalOceanService = require('../services/digitalOceanService');

/**
 * Roll the reference forward to an already-uploaded image URL.
 * Seeds faceFirstImage + avatar on the first capture (when empty).
 */
async function setFaceReferenceUrl(staffId, url) {
    if (!staffId || !url) return;
    try {
        const staffDoc = await Staff.findById(staffId).select('faceFirstImage').lean();
        const update = { faceReferenceImage: url };
        if (!staffDoc?.faceFirstImage) {
            // First capture ever (in practice the first punch — punch-in is required
            // before any break/permission): this image becomes the permanent first
            // image AND the profile photo, overwriting any existing avatar.
            update.faceFirstImage = url;
            update.faceFirstImageAt = new Date();
            update.avatar = url;
        }
        await Staff.findByIdAndUpdate(staffId, update);
    } catch (e) {
        console.error('[FaceReference] setFaceReferenceUrl failed', String(staffId), e?.message);
    }
}

/**
 * Roll the reference from a selfie that is NOT yet on Spaces (base64 / data-URL):
 * uploads it, then rolls the reference. Used by flows (custom permission) that
 * store the selfie inline rather than as a URL. Fire-and-forget; errors are logged.
 */
async function rollFaceReferenceFromSelfie(staffId, selfie, req, companyId, employeeName, type) {
    if (!staffId || !selfie) return;
    try {
        let base64Data = String(selfie);
        if (base64Data.startsWith('data:image')) {
            base64Data = base64Data.replace(/^data:image\/\w+;base64,/, '');
        }
        const buffer = Buffer.from(base64Data, 'base64');
        if (!buffer || buffer.length === 0) return;
        const result = await digitalOceanService.uploadAttendanceImage(
            buffer, req, companyId, employeeName || 'unknown', type || 'permission'
        );
        if (result?.success && result.url) await setFaceReferenceUrl(staffId, result.url);
    } catch (e) {
        console.error('[FaceReference] rollFaceReferenceFromSelfie failed', String(staffId), e?.message);
    }
}

module.exports = { setFaceReferenceUrl, rollFaceReferenceFromSelfie };
