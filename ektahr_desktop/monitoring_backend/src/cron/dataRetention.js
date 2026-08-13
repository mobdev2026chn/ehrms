require('dotenv').config();
const mongoose = require('../config/mongoose');
const cloudinary = require('cloudinary').v2;

const connectDB = require('../config/db');
const ActivityLog = require('../models/ActivityLog');
const Screenshot = require('../models/Screenshot');
const MonitoringSettings = require('../models/MonitoringSettings');

cloudinary.config({
    cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
    api_key: process.env.CLOUDINARY_API_KEY,
    api_secret: process.env.CLOUDINARY_API_SECRET
});

async function runRetention() {
    await connectDB();

    const tenants = await MonitoringSettings.find().select('businessId tenantId dataRetention').lean();
    const activityRetention = 90;
    const screenshotRetention = 30;

    const now = new Date();
    const activityCutoff = new Date(now);
    activityCutoff.setDate(activityCutoff.getDate() - activityRetention);

    const screenshotCutoff = new Date(now);
    screenshotCutoff.setDate(screenshotCutoff.getDate() - screenshotRetention);

    let activityDeleted = 0;
    let screenshotsDeleted = 0;

    for (const t of tenants) {
        const tenantId = t.tenantId ?? t.businessId;
        if (!tenantId) continue;
        const dr = t.dataRetention ?? {};
        const aid = dr.activityLogsDays ?? activityRetention;
        const sid = dr.screenshotsDays ?? screenshotRetention;
        const acut = new Date(now);
        acut.setDate(acut.getDate() - aid);
        const scut = new Date(now);
        scut.setDate(scut.getDate() - sid);

        const ar = await ActivityLog.deleteMany({ tenantId, timestamp: { $lt: acut } });
        activityDeleted += ar.deletedCount;

        const screenshots = await Screenshot.find({ tenantId, timestamp: { $lt: scut } }).lean();
        for (const s of screenshots) {
            try {
                await cloudinary.uploader.destroy(s.cloudinaryPublicId);
            } catch (e) { /* ignore */ }
        }
        const sr = await Screenshot.deleteMany({ tenantId, timestamp: { $lt: scut } });
        screenshotsDeleted += sr.deletedCount;
    }

    const defaultCutoff = new Date(now);
    defaultCutoff.setDate(defaultCutoff.getDate() - activityRetention);
    const orphanActivity = await ActivityLog.deleteMany({ timestamp: { $lt: defaultCutoff } });
    activityDeleted += orphanActivity.deletedCount;

    process.exit(0);
}

runRetention().catch(() => process.exit(1));
