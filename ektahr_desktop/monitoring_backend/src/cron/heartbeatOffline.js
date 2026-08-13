require('dotenv').config();
const mongoose = require('../config/mongoose');
const connectDB = require('../config/db');
const Device = require('../models/Device');

const OFFLINE_THRESHOLD_MS = 10 * 60 * 1000;

async function markOfflineDevices() {
    await connectDB();

    const cutoff = new Date(Date.now() - OFFLINE_THRESHOLD_MS);
    const result = await Device.updateMany(
        { lastSeenAt: { $lt: cutoff }, isActive: true },
        { isActive: false, status: 'inactive' }
    );

}

markOfflineDevices()
    .then(() => process.exit(0))
    .catch(() => process.exit(1));
