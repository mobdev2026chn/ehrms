const crypto = require('crypto');
const LiveSession = require('../models/LiveSession');
const Device = require('../models/Device');

/**
 * POST /api/live-stream/start
 * Create a new live screen viewing session for an active employee device
 */
exports.startSession = async (req, res) => {
    try {
        const { deviceId, employeeId, tenantId, viewerUserId, viewerName, quality } = req.body;

        if (!deviceId) {
            return res.status(400).json({ success: false, message: 'Device ID is required.' });
        }

        // Validate device exists and is currently online
        const device = await Device.findOne({ deviceId }).select('isActive status employeeID tenantId machineName').lean();

        if (!device) {
            return res.status(404).json({ success: false, message: 'This device was not found.' });
        }

        if (!device.isActive || device.status !== 'active') {
            return res.status(400).json({
                success: false,
                message: 'This device is currently offline.',
                code: 'DEVICE_OFFLINE'
            });
        }

        const effectiveEmployeeId = employeeId || device.employeeID;
        const effectiveTenantId = tenantId || device.tenantId;

        // Create unique session ID
        const liveSessionId = `ls_${Date.now()}_${crypto.randomBytes(4).toString('hex')}`;

        const session = await LiveSession.create({
            liveSessionId,
            tenantId: effectiveTenantId,
            employeeId: effectiveEmployeeId,
            deviceId,
            viewerUserId: viewerUserId || null,
            viewerName: viewerName || 'HR / Manager',
            startedAt: new Date(),
            status: 'connecting',
            quality: ['low', 'medium', 'high'].includes(quality) ? quality : 'high'
        });

        const proxyWsUrl = process.env.LIVE_STREAM_PROXY_WS_URL || 'ws://localhost:9003';

        return res.status(200).json({
            success: true,
            liveSessionId: session.liveSessionId,
            deviceId: session.deviceId,
            status: session.status,
            proxyWsUrl,
            startedAt: session.startedAt
        });
    } catch (error) {
        console.error('Error starting live session:', error);
        return res.status(500).json({
            success: false,
            message: 'Unable to connect to the employee device. Please try again later.'
        });
    }
};

/**
 * POST /api/live-stream/end
 * End an existing live screen viewing session and log audit details
 */
exports.endSession = async (req, res) => {
    try {
        const { liveSessionId, disconnectReason } = req.body;

        if (!liveSessionId) {
            return res.status(400).json({ success: false, message: 'Live session ID is required.' });
        }

        const session = await LiveSession.findOne({ liveSessionId });

        if (!session) {
            return res.status(404).json({ success: false, message: 'Live session not found.' });
        }

        const endedAt = new Date();
        const durationSeconds = Math.max(0, Math.round((endedAt.getTime() - new Date(session.startedAt).getTime()) / 1000));

        session.endedAt = endedAt;
        session.durationSeconds = durationSeconds;
        session.status = 'ended';
        if (disconnectReason) {
            session.disconnectReason = disconnectReason;
        }

        await session.save();

        console.log(`[LiveStream] Session ${liveSessionId} ended. Duration: ${durationSeconds}s`);

        return res.status(200).json({
            success: true,
            liveSessionId: session.liveSessionId,
            durationSeconds,
            status: 'ended'
        });
    } catch (error) {
        console.error('Error ending live session:', error);
        return res.status(500).json({ success: false, message: 'Failed to terminate live session cleanly.' });
    }
};

/**
 * GET /api/live-stream/session/:liveSessionId
 * Get current session details
 */
exports.getSessionStatus = async (req, res) => {
    try {
        const { liveSessionId } = req.params;
        const session = await LiveSession.findOne({ liveSessionId }).lean();

        if (!session) {
            return res.status(404).json({ success: false, message: 'Live session not found.' });
        }

        const device = await Device.findOne({ deviceId: session.deviceId }).select('isActive status lastSeenAt').lean();

        return res.status(200).json({
            success: true,
            session,
            deviceIsOnline: !!(device && device.isActive && device.status === 'active')
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: 'Failed to retrieve session status.' });
    }
};

/**
 * PUT /api/live-stream/session/metrics
 * Update session metrics (status, FPS, resolution) from Stream Proxy
 */
exports.updateSessionMetrics = async (req, res) => {
    try {
        const { liveSessionId, status, fps, resolution } = req.body;
        const updateData = {};

        if (status) updateData.status = status;
        if (typeof fps === 'number') updateData.fps = fps;
        if (resolution) updateData.resolution = resolution;

        const session = await LiveSession.findOneAndUpdate(
            { liveSessionId },
            { $set: updateData },
            { new: true }
        );

        return res.status(200).json({ success: true, session });
    } catch (error) {
        return res.status(500).json({ success: false, message: 'Failed to update session metrics.' });
    }
};
