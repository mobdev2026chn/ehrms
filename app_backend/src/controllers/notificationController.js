const Staff = require('../models/Staff');
const fcmService = require('../services/fcmService');

/**
 * POST /api/notifications/send-push (internal: called by web backend to send FCM to mobile app)
 * Body: { fcmToken?: string, staffId?: string, title: string, body: string, data?: object }
 * If fcmToken provided, send to that token. If staffId provided (and no fcmToken), look up Staff.fcmToken and send.
 * On invalid token, clears that token from Staff so the app can re-register on next open.
 */
const sendPush = async (req, res) => {
    try {
        const body = req.body || {};
        const title = body.title;
        const staffId = body.staffId;
        const hasFcmToken = !!(body.fcmToken && String(body.fcmToken).trim());
        console.log('[NOTIFICATION] RECEIVED send-push request: title=', title, 'staffId=', staffId || 'n/a', 'hasFcmToken=', hasFcmToken, 'dataKeys=', body.data ? Object.keys(body.data) : []);

        let fcmToken = body.fcmToken;
        const data = body.data || {};
        const bodyText = body.body;
        console.log('[notificationController] send-push received: title=', title, 'body=', (bodyText || '').substring(0, 60), 'data.type=', data?.type, 'staffId=', staffId || 'n/a', 'hasFcmToken=', !!fcmToken);

        if (!title || typeof title !== 'string') {
            console.log('[notificationController] send-push rejected: title required');
            return res.status(400).json({
                success: false,
                error: { message: 'title is required' },
            });
        }
        if (!fcmToken && staffId) {
            const staff = await Staff.findById(staffId).select('fcmToken').lean();
            fcmToken = staff?.fcmToken;
            console.log('[notificationController] send-push looked up token by staffId:', staffId, 'found=', !!fcmToken);
        }
        if (!fcmToken || typeof fcmToken !== 'string' || !fcmToken.trim()) {
            console.log('[NOTIFICATION] send-push skip: no FCM token (staff may not have app open or token not registered)');
            return res.json({ success: true, message: 'No FCM token, skip' });
        }

        const tokenPreview = fcmToken.length > 20 ? fcmToken.substring(0, 10) + '...' + fcmToken.slice(-8) : fcmToken;
        console.log('[NOTIFICATION] send-push calling FCM: token=', tokenPreview, 'title=', title);
        const result = await fcmService.sendToToken(fcmToken.trim(), {
            title,
            body: bodyText || '',
            data: typeof data === 'object' ? data : {},
        });
        if (!result.success) {
            console.error('[NOTIFICATION] send-push FCM failed:', result.error);
            if (result.invalidToken) {
                if (staffId) {
                    await Staff.findByIdAndUpdate(staffId, { $unset: { fcmToken: 1 } });
                    console.log('[NOTIFICATION] send-push: cleared invalid fcmToken for staffId=', staffId);
                } else {
                    const r = await Staff.updateMany(
                        { fcmToken: fcmToken.trim() },
                        { $unset: { fcmToken: 1 } }
                    );
                    if (r.modifiedCount > 0) {
                        console.log('[NOTIFICATION] send-push: cleared invalid fcmToken from', r.modifiedCount, 'Staff doc(s)');
                    }
                }
            }
            return res.status(500).json({ success: false, error: { message: result.error || 'FCM send failed' } });
        }
        console.log('[NOTIFICATION] send-push success: FCM accepted message, title=', title);
        return res.json({ success: true, message: 'Push sent' });
    } catch (error) {
        console.error('[notificationController] sendPush:', error);
        return res.status(500).json({
            success: false,
            error: { message: error.message },
        });
    }
};

/**
 * POST /api/notifications/fcm-token (protected: requires Bearer token)
 * Body: { fcmToken: string } to register, or { fcmToken: "" } / {} to clear on logout
 * Uses the logged-in staff id from auth (req.staff._id). Register: store token for push. Clear: remove token so we stop sending to that device until they log in again.
 */
const registerFcmToken = async (req, res) => {
    try {
        const staffId = req.staff?._id;
        const fcmTokenRaw = req.body?.fcmToken;
        const hasToken = fcmTokenRaw !== undefined && fcmTokenRaw !== null && typeof fcmTokenRaw === 'string' && fcmTokenRaw.trim().length > 0;
        // Log as soon as request is received (for debugging "notification not receiving")
        console.log('[NOTIFICATION] RECEIVED fcm-token request: staffId=', staffId ? String(staffId) : 'null', 'hasFcmToken=', hasToken, 'tokenLength=', typeof fcmTokenRaw === 'string' ? fcmTokenRaw.length : 0);

        console.log('[FCM] fcm-token POST: staffId=', staffId ? String(staffId) : 'null', 'req.staff=', !!req.staff);
        if (!staffId) {
            console.log('[FCM] fcm-token: 401 – no staffId (user not linked to staff?)');
            return res.status(401).json({ success: false, error: { message: 'Not authorized' } });
        }
        const fcmToken = req.body?.fcmToken;
        const staffIdStr = staffId.toString();

        if (fcmToken === undefined || fcmToken === null || (typeof fcmToken === 'string' && fcmToken.trim() === '')) {
            const before = await Staff.findById(staffId).select('fcmToken').lean();
            const hadToken = before && before.fcmToken && String(before.fcmToken).trim().length > 0;
            await Staff.findByIdAndUpdate(staffId, { $unset: { fcmToken: 1 } });
            console.log('[FCM] Logout: cleared fcmToken for staffId=', staffIdStr, 'hadToken=', hadToken, '– device will not receive push until they log in again');
            return res.json({ success: true, message: 'FCM token cleared' });
        }

        if (typeof fcmToken !== 'string') {
            return res.status(400).json({
                success: false,
                error: { message: 'fcmToken must be a string' },
            });
        }

        const tokenTrimmed = fcmToken.trim();
        if (!tokenTrimmed) {
            await Staff.findByIdAndUpdate(staffId, { $unset: { fcmToken: 1 } });
            console.log('[FCM] Logout: cleared fcmToken for staffId=', staffIdStr, '(empty string)');
            return res.json({ success: true, message: 'FCM token cleared' });
        }

        // Ensure this token is only stored for THIS staff: remove it from any other staff document
        await Staff.updateMany(
            { fcmToken: tokenTrimmed, _id: { $ne: staffId } },
            { $unset: { fcmToken: 1 } }
        );
        await Staff.findByIdAndUpdate(staffId, { $set: { fcmToken: tokenTrimmed } });
        const tokenPreview = tokenTrimmed.length > 20 ? tokenTrimmed.substring(0, 10) + '...' + tokenTrimmed.slice(-6) : tokenTrimmed;
        console.log('[FCM] fcm-token: Registered OK staffId=', staffIdStr, 'tokenLength=', tokenTrimmed.length, 'tokenPreview=', tokenPreview);
        return res.json({ success: true, message: 'FCM token registered' });
    } catch (error) {
        console.error('[notificationController] registerFcmToken:', error);
        return res.status(500).json({
            success: false,
            error: { message: error.message },
        });
    }
};

module.exports = {
    registerFcmToken,
    sendPush,
};
