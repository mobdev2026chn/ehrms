const Bull = require('bull');

const QUEUE_NAME = process.env.REDIS_QUEUE_NAME || 'monitoring_processing_queue';
const REDIS_URL = process.env.REDIS_URL || 'redis://localhost:6379';
// Default: no Redis. Set USE_REDIS=true to use Redis queue + Worker (recommended for 50+ users).
const USE_REDIS = process.env.USE_REDIS === 'true' || process.env.USE_REDIS === '1';
// Max concurrent inline processing when USE_REDIS=false. Prevents crash under load.
const INLINE_CONCURRENCY = Math.min(20, Math.max(5, parseInt(process.env.INLINE_CONCURRENCY, 10) || 8));

/** Simple concurrency limiter: run at most N tasks at a time. */
const inlineQueue = (() => {
    let running = 0;
    const waiters = [];
    const runNext = () => {
        while (running < INLINE_CONCURRENCY && waiters.length > 0) {
            running++;
            const { fn, resolve, reject } = waiters.shift();
            Promise.resolve(fn()).then(resolve, (err) => { reject(err); }).finally(() => { running--; runNext(); });
        }
    };
    return (fn) => new Promise((resolve, reject) => {
        waiters.push({ fn, resolve, reject });
        runNext();
    });
})();

let activityQueue = null;

const getActivityQueue = () => {
    if (!activityQueue) {
        activityQueue = new Bull(QUEUE_NAME, REDIS_URL, {
            defaultJobOptions: {
                attempts: 5,
                backoff: { type: 'exponential', delay: 2000 },
                removeOnComplete: 100
            }
        });
    }
    return activityQueue;
};

exports.uploadActivity = async (req, res) => {
    try {
        const { encryptedKey, encryptedPayload, metadata } = req.body;

        if (!encryptedKey || !encryptedPayload || !metadata) {
            return res.status(400).json({
                success: false,
                message: 'encryptedKey, encryptedPayload, metadata are required'
            });
        }

        const { deviceId, tenantId, type, timestamp } = metadata;
        if (!deviceId || !tenantId || !type || !timestamp) {
            return res.status(400).json({
                success: false,
                message: 'metadata must include deviceId, tenantId, type, timestamp'
            });
        }

        if (!USE_REDIS) {
            const activityProcessor = require('../services/activityProcessor');
            const payload = { encryptedKey, encryptedPayload, metadata: { deviceId, tenantId, type, timestamp } };
            try {
                const result = await inlineQueue(() => activityProcessor.processPayload(payload));
                return res.status(200).json({ success: true });
            } catch (err) {
<<<<<<< HEAD
                const isScreenshotTooSoon = metadata?.type === 'screenshot' && /too soon|too soon/i.test(err.message || '');
                if (isScreenshotTooSoon) {
=======
                if (activityProcessor.isSkippableTrackingError(err)) {
>>>>>>> development
                    return res.status(200).json({ success: true, skipped: true });
                }
                console.error('Error (activity upload):', err.message || err);
                return res.status(500).json({ success: false, message: err.message });
            }
        }

        const queue = getActivityQueue();
        const job = await queue.add({
            encryptedKey,
            encryptedPayload,
            metadata: { deviceId, tenantId, type, timestamp }
        });
        res.status(200).json({ success: true });
    } catch (error) {
        if (USE_REDIS && (error.code === 'ECONNREFUSED' || (error.message && error.message.includes('max retries')))) {
            try {
                const activityProcessor = require('../services/activityProcessor');
                await inlineQueue(() => activityProcessor.processPayload(req.body));
                return res.status(200).json({ success: true });
            } catch (fallbackErr) {
<<<<<<< HEAD
                const meta = req.body?.metadata || {};
                const isScreenshotTooSoon = meta?.type === 'screenshot' && /too soon/i.test(fallbackErr.message || '');
                if (isScreenshotTooSoon) {
=======
                if (activityProcessor.isSkippableTrackingError(fallbackErr)) {
>>>>>>> development
                    return res.status(200).json({ success: true, skipped: true });
                }
                console.error('Error (activity upload fallback):', fallbackErr.message || fallbackErr);
                return res.status(500).json({ success: false, message: fallbackErr.message });
            }
        }
        console.error('Error (activity upload):', error.message || error);
        res.status(500).json({ success: false, message: error.message });
    }
};
