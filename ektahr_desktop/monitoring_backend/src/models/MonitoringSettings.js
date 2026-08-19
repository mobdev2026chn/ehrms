const mongoose = require('../config/mongoose');

const monitoringSettingsSchema = new mongoose.Schema({
    businessId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company', required: true, unique: true },
    tenantId: { type: mongoose.Schema.Types.ObjectId, ref: 'Company' }, // alias for shared collection index (same as businessId)

    monitoringEnabled: { type: Boolean, default: true },

    screenshotSettings: {
        enabled: { type: Boolean, default: true },
        randomMode: { type: Boolean, default: false },
        quality: { type: String, enum: ['low', 'medium', 'high'], default: 'medium' },
        blurSensitiveInfo: {
            enabled: { type: Boolean, default: true },
            rules: [{
                type: { type: String },
                value: String,
                processName: String,
                blurMode: { type: String } // 'fullWindow' | 'region'
            }]
        }
    },

    activityTracking: {
        enabled: { type: Boolean, default: true },
        trackKeyboard: { type: Boolean, default: true },
        trackMouseClicks: { type: Boolean, default: true },
        trackScroll: { type: Boolean, default: true },
        trackActiveWindow: { type: Boolean, default: true }
    },

    productivitySettings: {
        enabled: { type: Boolean, default: true },
        measurementWindowSeconds: { type: Number, default: 60 },
        expectedActivityPerMinute: {
            keystrokes: { type: Number, default: 40 },
            mouseClicks: { type: Number, default: 20 },
            scrolls: { type: Number, default: 10 }
        },
        weights: {
            activityWeight: { type: Number, default: 0.7 },
            idleWeight: { type: Number, default: 0.3 }
        },
        scoreRange: {
            min: { type: Number, default: 0 },
            max: { type: Number, default: 100 }
        }
    },

    idleSettings: {
        idleTimeMinutes: { type: Number, default: 5 }
    },

    breakSettings: {
        allowedBreaksPerDay: { type: Number, default: 2 },
        maxBreakDurationMinutes: { type: Number, default: 15 }
    },

    staffControl: {
        disableTrackingForStaffIds: [{ type: mongoose.Schema.Types.ObjectId, ref: 'Staff' }]
    },

    syncSettings: {
        activityUploadIntervalSeconds: { type: Number, default: 10 },
        screenshotUploadIntervalMinutes: { type: Number, default: 5 },
        retryFailedUploads: { type: Boolean, default: true }
    },

    deviceSettings: {
        allowMultipleDevices: { type: Boolean, default: false },
        heartbeatTimeoutMinutes: { type: Number, default: 10 }
    },

    dataRetention: {
        activityLogsDays: { type: Number, default: 90 },
        screenshotsDays: { type: Number, default: 30 }
    },

    alerts: {
        idleAlert: { type: Boolean, default: true },
        deviceOfflineAlert: { type: Boolean, default: true },
        breakExceededAlert: { type: Boolean, default: true }
    }
}, { timestamps: true, collection: 'monitoringsettings' });

module.exports = mongoose.model('MonitoringSettings', monitoringSettingsSchema);
