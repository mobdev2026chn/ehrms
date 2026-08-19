/**
 * Seed monitoringsettings collection.
 * Creates MonitoringSettings for each Company (tenant) that doesn't have one.
 * Run: node scripts/seed-monitoringsettings.js
 * Or with specific businessId: BUSINESS_ID=69a13b64ce4d07bf2d7d280e node scripts/seed-monitoringsettings.js
 */
require('dotenv').config();
const path = require('path');
const mongoose = require('mongoose');

const connectDB = require('../src/config/db');
const MonitoringSettings = require('../src/models/MonitoringSettings');

const appBackendRoot = path.join(__dirname, '../../../', 'app_backend');
const Company = require(path.join(appBackendRoot, 'src', 'models', 'Company'));

const DEFAULT_SETTINGS = {
    monitoringEnabled: true,
    screenshotSettings: {
        enabled: true,
        randomMode: false,
        quality: 'medium',
        blurSensitiveInfo: { enabled: true, rules: [] }
    },
    activityTracking: {
        enabled: true,
        trackKeyboard: true,
        trackMouseClicks: true,
        trackScroll: true,
        trackActiveWindow: true
    },
    productivitySettings: {
        enabled: true,
        measurementWindowSeconds: 60,
        expectedActivityPerMinute: { keystrokes: 40, mouseClicks: 20, scrolls: 10 },
        weights: { activityWeight: 0.7, idleWeight: 0.3 },
        scoreRange: { min: 0, max: 100 }
    },
    idleSettings: { idleTimeMinutes: 5 },
    breakSettings: { allowedBreaksPerDay: 2, maxBreakDurationMinutes: 15 },
    staffControl: { disableTrackingForStaffIds: [] },
    syncSettings: {
        activityUploadIntervalSeconds: 60,
        screenshotUploadIntervalMinutes: 2,
        retryFailedUploads: true
    },
    deviceSettings: { allowMultipleDevices: false, heartbeatTimeoutMinutes: 10 },
    dataRetention: { activityLogsDays: 90, screenshotsDays: 30 },
    alerts: { idleAlert: true, deviceOfflineAlert: true, breakExceededAlert: true }
};

async function main() {
    await connectDB();

    const businessIdArg = process.env.BUSINESS_ID;
    let companyIds = [];

    if (businessIdArg) {
        const id = new mongoose.Types.ObjectId(businessIdArg);
        const c = await Company.findById(id).select('_id').lean();
        if (!c) {
            console.error('Company not found for BUSINESS_ID:', businessIdArg);
            process.exit(1);
        }
        companyIds = [c._id];
        console.log('Seeding for businessId:', businessIdArg);
    } else {
        const companies = await Company.find({}).select('_id').lean();
        companyIds = companies.map(c => c._id);
        console.log('Found', companyIds.length, 'companies. Seeding monitoringsettings...');
    }

    let created = 0;
    let skipped = 0;
    for (const businessId of companyIds) {
        const existing = await MonitoringSettings.findOne({ businessId }).lean();
        if (existing) {
            console.log('  Skip (exists):', businessId.toString());
            skipped++;
            continue;
        }
        await MonitoringSettings.create({
            businessId,
            tenantId: businessId,
            ...DEFAULT_SETTINGS
        });
        console.log('  Created:', businessId.toString());
        created++;
    }

    console.log('\nDone. Created:', created, '| Skipped:', skipped);
    process.exit(0);
}

main().catch((err) => {
    console.error('Seed failed:', err.message);
    process.exit(1);
});
