const path = require('path');
const Break = require('../models/Break');
const Device = require('../models/Device');
const MonitoringSettings = require('../models/MonitoringSettings');
const Staff = require(path.join(__dirname, '../../../../app_backend/src/models/Staff'));

const SOURCE_SOFTWARE = 'software';
const SOURCE_WEB = 'web';
const SOURCE_APP = 'app';

<<<<<<< HEAD
=======
function buildBreakLocation(payload = {}) {
    const latitude = payload.latitude ?? payload.lat ?? null;
    const longitude = payload.longitude ?? payload.lng ?? null;
    return {
        latitude: latitude != null ? Number(latitude) : null,
        longitude: longitude != null ? Number(longitude) : null,
        address: payload.address || '',
        area: payload.area || '',
        city: payload.city || '',
        pincode: payload.pincode || ''
    };
}

function serializeBreak(doc) {
    if (!doc) return null;
    return {
        id: doc._id?.toString?.() || doc.id,
        employeeID: doc.employeeID?.toString?.() || doc.employeeID,
        deviceId: doc.deviceId || '',
        tenantId: doc.tenantId?.toString?.() || doc.tenantId,
        startTime: doc.startTime,
        endTime: doc.endTime,
        totalSeconds: doc.totalSeconds,
        breakMin: doc.breakMin ?? 0,
        breakCount: doc.breakCount ?? 0,
        breakFineMins: doc.breakFineMins ?? 0,
        breakFineAmount: doc.breakFineAmount ?? 0,
        source: doc.source || '',
        breakStartSelfie: doc.breakStartSelfie || '',
        breakEndSelfie: doc.breakEndSelfie || '',
        breakStartLocation: doc.breakStartLocation || {},
        breakEndLocation: doc.breakEndLocation || {}
    };
}

async function getActiveBreakForDevice(device) {
    return Break.findOne({
        employeeID: device.employeeID,
        tenantId: device.tenantId,
        endTime: null
    }).sort({ startTime: -1 });
}

>>>>>>> development
/** GET /break/limit-check - Check if user can start another break today. Returns { canStart, todayCount, allowedBreaksPerDay, message }. */
exports.checkLimit = async (req, res) => {
    try {
        const device = req.device;
        if (!device?.employeeID || !device?.tenantId) {
            return res.status(401).json({ message: 'Device context missing' });
        }
        const monSettings = await MonitoringSettings.findOne({ businessId: device.tenantId }).lean();
        const allowedBreaksPerDay = monSettings?.breakSettings?.allowedBreaksPerDay ?? 2;
        const now = new Date();
        const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0, 0);
        const endOfToday = new Date(startOfToday);
        endOfToday.setDate(endOfToday.getDate() + 1);
        const todayCount = await Break.countDocuments({
            employeeID: device.employeeID,
            tenantId: device.tenantId,
            startTime: { $gte: startOfToday, $lt: endOfToday }
        });
        const canStart = todayCount < allowedBreaksPerDay;
        const message = canStart ? null : `You can take only ${allowedBreaksPerDay} break(s) per day.`;
        res.status(200).json({ canStart, todayCount, allowedBreaksPerDay, message });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

/** POST /break/start - Insert break document when user starts tea break. (Use /pause/start and /meeting/start for pause and meeting.) */
exports.startBreak = async (req, res) => {
    try {
<<<<<<< HEAD
        const { startTime, source } = req.body;
=======
        const { startTime, source, breakStartSelfie } = req.body;
>>>>>>> development
        const device = req.device;
        if (!device?.employeeID || !device?.deviceId || !device?.tenantId) {
            return res.status(401).json({ message: 'Device context missing' });
        }
        if (!startTime) {
            return res.status(400).json({ message: 'startTime required' });
        }
        const monSettings = await MonitoringSettings.findOne({ businessId: device.tenantId }).lean();
        const allowedBreaksPerDay = monSettings?.breakSettings?.allowedBreaksPerDay ?? 2;
        const now = new Date();
        const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0, 0);
        const endOfToday = new Date(startOfToday);
        endOfToday.setDate(endOfToday.getDate() + 1);
        const todayCount = await Break.countDocuments({
            employeeID: device.employeeID,
            tenantId: device.tenantId,
            startTime: { $gte: startOfToday, $lt: endOfToday }
        });
        if (todayCount >= allowedBreaksPerDay) {
            return res.status(403).json({
                success: false,
                message: `You can take only ${allowedBreaksPerDay} break(s) per day.`
            });
        }
<<<<<<< HEAD
=======
        const activeBreak = await getActiveBreakForDevice(device);
        if (activeBreak) {
            return res.status(409).json({
                success: false,
                message: 'You are already on break. End that break to start a new one.',
                activeBreak: serializeBreak(activeBreak)
            });
        }
>>>>>>> development
        const normalizedSource = [SOURCE_SOFTWARE, SOURCE_WEB, SOURCE_APP].includes(source) ? source : SOURCE_SOFTWARE;
        const doc = await Break.create({
            employeeID: device.employeeID,
            deviceId: device.deviceId,
            tenantId: device.tenantId,
            startTime: new Date(startTime),
<<<<<<< HEAD
            source: normalizedSource
=======
            source: normalizedSource,
            breakStartSelfie: breakStartSelfie || '',
            breakStartLocation: buildBreakLocation(req.body)
>>>>>>> development
        });
        await Device.updateOne({ deviceId: device.deviceId }, { $set: { status: 'break', lastSeenAt: new Date() } });
        await Staff.updateOne({ _id: device.employeeID }, { $set: { monitoringStatus: 'break' } });
        const staffDoc = await Staff.findById(device.employeeID).select('name employeeId').lean();
        const displayName = (staffDoc?.name || staffDoc?.employeeId || 'Unknown').trim();
        console.log(`${displayName} break`);
<<<<<<< HEAD
        res.status(201).json({ success: true, breakId: doc._id.toString() });
=======
        res.status(201).json({
            success: true,
            breakId: doc._id.toString(),
            break: serializeBreak(doc)
        });
>>>>>>> development
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};

/** PATCH /break/:id - Update break document when user ends break. */
exports.endBreak = async (req, res) => {
    try {
        const { id } = req.params;
<<<<<<< HEAD
        const { endTime, totalSeconds } = req.body;
=======
        const { endTime, totalSeconds, breakEndSelfie } = req.body;
>>>>>>> development
        const device = req.device;
        if (!device?.employeeID || !device?.deviceId || !device?.tenantId) {
            return res.status(401).json({ message: 'Device context missing' });
        }
        if (!id || !endTime || typeof totalSeconds !== 'number') {
            return res.status(400).json({ message: 'id, endTime, totalSeconds required' });
        }
        const doc = await Break.findOneAndUpdate(
<<<<<<< HEAD
            { _id: id, deviceId: device.deviceId },
            { $set: { endTime: new Date(endTime), totalSeconds } },
            { new: true }
        );
        if (!doc) {
            return res.status(404).json({ message: 'Break not found or not owned by this device' });
        }
        await Device.updateOne({ deviceId: device.deviceId }, { $set: { status: 'active', lastSeenAt: new Date() } });
=======
            {
                _id: id,
                employeeID: device.employeeID,
                tenantId: device.tenantId,
                endTime: null
            },
            {
                $set: {
                    endTime: new Date(endTime),
                    totalSeconds,
                    breakEndSelfie: breakEndSelfie || '',
                    breakEndLocation: buildBreakLocation(req.body)
                }
            },
            { new: true }
        );
        if (!doc) {
            return res.status(404).json({ message: 'Break not found or already ended' });
        }
        const allowedBreakMin = 5; // TEMP for testing; set 60 in production
        const dayStart = new Date(doc.endTime || endTime);
        dayStart.setUTCHours(0, 0, 0, 0);
        const dayEnd = new Date(dayStart);
        dayEnd.setUTCDate(dayEnd.getUTCDate() + 1);
        const dayBreaks = await Break.find({
            employeeID: device.employeeID,
            tenantId: device.tenantId,
            startTime: { $gte: dayStart, $lt: dayEnd },
            endTime: { $ne: null }
        }).select('totalSeconds startTime endTime').lean();
        const totalBreakMin = dayBreaks.reduce((sum, b) => {
            const secs = Number(b?.totalSeconds);
            if (Number.isFinite(secs) && secs >= 0) return sum + Math.round(secs / 60);
            const st = b?.startTime ? new Date(b.startTime).getTime() : 0;
            const et = b?.endTime ? new Date(b.endTime).getTime() : 0;
            if (!st || !et || et < st) return sum;
            return sum + Math.round((et - st) / (1000 * 60));
        }, 0);
        const totalBreakCount = dayBreaks.length;
        const breakFineMins = Math.max(0, totalBreakMin - allowedBreakMin);
        await Break.updateOne(
            { _id: doc._id },
            { $set: { breakMin: totalBreakMin, breakCount: totalBreakCount, breakFineMins, breakFineAmount: doc.breakFineAmount || 0 } }
        );
        doc.breakMin = totalBreakMin;
        doc.breakCount = totalBreakCount;
        doc.breakFineMins = breakFineMins;
        doc.breakFineAmount = doc.breakFineAmount || 0;
        await Device.updateOne({ deviceId: doc.deviceId }, { $set: { status: 'active', lastSeenAt: new Date() } });
>>>>>>> development
        await Staff.updateOne({ _id: device.employeeID }, { $set: { monitoringStatus: 'active' } });
        let alert = null;
        const monSettings = await MonitoringSettings.findOne({ businessId: device.tenantId }).lean();
        const breakExceededEnabled = monSettings?.alerts?.breakExceededAlert !== false;
        const maxDurationMinutes = monSettings?.breakSettings?.maxBreakDurationMinutes ?? 15;
        const maxDurationSeconds = maxDurationMinutes * 60;

        if (breakExceededEnabled && totalSeconds > maxDurationSeconds) {
            const exceededMinutes = Math.round((totalSeconds - maxDurationSeconds) / 60);
            alert = {
                type: 'break_exceeded',
                message: `Break duration exceeded the allowed ${maxDurationMinutes} minutes by ${exceededMinutes} minutes.`,
                exceededMinutes,
                maxBreakDurationMinutes: maxDurationMinutes
            };
        }
<<<<<<< HEAD

        res.status(200).json({ success: true, breakId: doc._id.toString(), alert });
=======
        res.status(200).json({
            success: true,
            breakId: doc._id.toString(),
            break: serializeBreak(doc),
            alert
        });
>>>>>>> development
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};
