require('dotenv').config();
const Bull = require('bull');
const connectDB = require('./src/config/db');
const activityProcessor = require('./src/services/activityProcessor');

const QUEUE_NAME = process.env.REDIS_QUEUE_NAME || 'monitoring_processing_queue';
const REDIS_URL = process.env.REDIS_URL || 'redis://localhost:6379';

const queue = new Bull(QUEUE_NAME, REDIS_URL, {
    defaultJobOptions: {
        attempts: 5,
        backoff: { type: 'exponential', delay: 2000 },
        removeOnComplete: 100
    }
});

const WORKER_CONCURRENCY = parseInt(process.env.WORKER_CONCURRENCY, 10) || 8;
queue.process(WORKER_CONCURRENCY, async (job) => {
    try {
        await activityProcessor.processPayload(job.data);
    } catch (err) {
        if (activityProcessor.isSkippableTrackingError(err)) {
            console.log('Worker job skipped:', err?.message || err);
            return { skipped: true, reason: err?.message || String(err) };
        }
        throw err;
    }
});

queue.on('failed', (job, err) => {
    console.error('Error (worker job failed):', err?.message || err);
});

const start = async () => {
    try {
        await connectDB();
        try {
            await Promise.race([
                queue.client.ping(),
                new Promise((_, reject) => setTimeout(() => reject(new Error('timeout')), 4000))
            ]);
        } catch (e) {
            console.warn('Worker warning: Redis ping failed, queue may be unavailable:', e?.message || e);
        }
        console.log(`Worker started. Queue=${QUEUE_NAME}, Concurrency=${WORKER_CONCURRENCY}`);
    } catch (err) {
        console.error('Worker startup failed:', err?.message || err);
        if (process.env.NODE_ENV !== 'production' && err?.stack) {
            console.error(err.stack);
        }
        process.exit(1);
    }
};

start();
