const express = require('express');
const router = express.Router();
const mongoose = require('../config/mongoose');
const ActivityLog = require('../models/ActivityLog');
const Screenshot = require('../models/Screenshot');

/** GET /api/debug/latest-logs?limit=10 - latest activity logs and screenshots (for testing) */
router.get('/latest-logs', async (req, res) => {
    try {
        const limit = Math.min(parseInt(req.query.limit, 10) || 10, 50);
        const [logs, screenshots] = await Promise.all([
            ActivityLog.find().sort({ timestamp: -1 }).limit(limit).lean(),
            Screenshot.find().sort({ timestamp: -1 }).limit(limit).lean()
        ]);
        res.json({
            activityLogsCount: logs.length,
            screenshotsCount: screenshots.length,
            activityLogs: logs.map(l => ({ _id: l._id, deviceId: l.deviceId, timestamp: l.timestamp, keystrokes: l.keystrokes, mouseClicks: l.mouseClicks })),
            screenshots: screenshots.map(s => ({ _id: s._id, deviceId: s.deviceId, timestamp: s.timestamp, hasUrl: !!s.secureUrl }))
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

module.exports = router;
