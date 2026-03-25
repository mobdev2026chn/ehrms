const path = require('path');
const Break = require(path.join(__dirname, '../../../ektahr_desktop/monitoring_backend/src/models/Break'));
const Device = require(path.join(__dirname, '../../../ektahr_desktop/monitoring_backend/src/models/Device'));
const Staff = require('../models/Staff');
const AttendanceLog = require('../models/AttendanceLog');
const digitalOceanService = require('../services/digitalOceanService');

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
    const startTime = doc.startTime ? new Date(doc.startTime) : null;
    const endTime = doc.endTime ? new Date(doc.endTime) : null;
    return {
        id: doc._id?.toString?.() || doc.id,
        employeeID: doc.employeeID?.toString?.() || doc.employeeID,
        tenantId: doc.tenantId?.toString?.() || doc.tenantId,
        deviceId: doc.deviceId || '',
        source: doc.source || '',
        startTime,
        endTime,
        totalSeconds: doc.totalSeconds ?? null,
        durationSeconds: !endTime && startTime ? Math.max(0, Math.floor((Date.now() - startTime.getTime()) / 1000)) : (doc.totalSeconds ?? 0),
        breakStartSelfie: doc.breakStartSelfie || '',
        breakEndSelfie: doc.breakEndSelfie || '',
        breakStartLocation: doc.breakStartLocation || {},
        breakEndLocation: doc.breakEndLocation || {}
    };
}

function buildAddressString(address, area, city, pincode) {
    return [address, area, city, pincode]
        .map(value => value == null ? '' : String(value).trim())
        .filter(Boolean)
        .join(', ');
}

async function createBreakLog({
    breakDoc,
    action,
    performedBy,
    performedByName,
    performedByEmail,
    selfieUrl,
    timestamp,
    startAddress,
    endAddress,
    startLocation,
    endLocation,
    totalSeconds,
    payload
}) {
    if (!breakDoc?._id || !performedBy) return;
    const logPayload = {
        attendanceId: breakDoc._id,
        action,
        performedBy,
        performedByName: performedByName || undefined,
        performedByEmail: performedByEmail || undefined,
        selfieUrl: selfieUrl || undefined,
        timestamp: timestamp || new Date(),
        notes: `Break ${action === 'BREAK_START' ? 'started' : 'ended'} from app`,
        newValue: payload
    };

    if (action === 'BREAK_START') {
        logPayload.breakStartDateTime = breakDoc.startTime || timestamp || undefined;
        logPayload.breakStartAddress = startAddress || undefined;
        logPayload.breakStartLocation = startLocation || undefined;
    } else if (action === 'BREAK_END') {
        logPayload.breakStartDateTime = breakDoc.startTime || undefined;
        logPayload.breakEndDateTime = breakDoc.endTime || timestamp || undefined;
        logPayload.totalBreakSeconds = totalSeconds ?? breakDoc.totalSeconds ?? undefined;
        logPayload.breakStartAddress = startAddress || undefined;
        logPayload.breakEndAddress = endAddress || undefined;
        logPayload.breakStartLocation = startLocation || undefined;
        logPayload.breakEndLocation = endLocation || undefined;
    }

    await AttendanceLog.create(logPayload)
        .catch(err => console.warn(`[AttendanceLog] ${action} create failed:`, err?.message));
}

async function uploadBreakSelfie(base64String, req, companyId, employeeName, type) {
    try {
        if (!base64String) return null;
        let base64Data = base64String;
        if (base64String.startsWith('data:image')) {
            base64Data = base64String.replace(/^data:image\/\w+;base64,/, '');
        }
        const buffer = Buffer.from(base64Data, 'base64');
        const now = new Date();
        const monthFolder = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
        const baseFolder = digitalOceanService.getBaseFolder(req);
        const targetFolder = `${baseFolder}/ekta_hr/break/s/${monthFolder}`;
        const fileName = digitalOceanService.generateSecureFileName(
            String(type || 'break-start').replace('-', '_'),
            'jpg'
        );
        const result = await digitalOceanService.uploadImage(buffer, targetFolder, {
            fileName,
            format: 'jpg'
        });
        return result.success ? result.url : null;
    } catch (error) {
        console.error('[Break] Selfie upload error:', error.message);
        return null;
    }
}

async function getActiveBreak(staff) {
    return Break.findOne({
        employeeID: staff._id,
        tenantId: staff.businessId,
        endTime: null
    }).sort({ startTime: -1 });
}

function getAppDeviceId(staffId) {
    return `app:${staffId}`;
}

exports.getCurrentBreak = async (req, res) => {
    try {
        if (!req.staff?._id) {
            return res.status(404).json({ success: false, message: 'Staff record not found' });
        }
        const staff = await Staff.findById(req.staff._id).select('_id businessId');
        if (!staff?.businessId) {
            return res.status(404).json({ success: false, message: 'Staff business not found' });
        }
        const activeBreak = await getActiveBreak(staff);
        return res.status(200).json({
            success: true,
            hasActiveBreak: !!activeBreak,
            data: serializeBreak(activeBreak)
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

exports.startBreak = async (req, res) => {
    try {
        const { latitude, longitude, selfie, startTime } = req.body;
        if (!req.staff?._id) {
            return res.status(404).json({ success: false, message: 'Staff record not found' });
        }
        if (latitude === undefined || longitude === undefined) {
            return res.status(400).json({ success: false, message: 'Location coordinates are missing' });
        }
        if (!selfie) {
            return res.status(400).json({ success: false, message: 'Break start selfie is required' });
        }

        const staff = await Staff.findById(req.staff._id).select('_id businessId name email userId');
        if (!staff?.businessId) {
            return res.status(404).json({ success: false, message: 'Staff business not found' });
        }

        const activeBreak = await getActiveBreak(staff);
        if (activeBreak) {
            return res.status(409).json({
                success: false,
                message: 'You are already on break. End that break to start a new one.',
                data: serializeBreak(activeBreak)
            });
        }

        const breakStartSelfie = await uploadBreakSelfie(
            selfie,
            req,
            String(staff.businessId),
            staff.name,
            'break-start'
        );

        const doc = await Break.create({
            employeeID: staff._id,
            deviceId: getAppDeviceId(staff._id),
            tenantId: staff.businessId,
            startTime: startTime ? new Date(startTime) : new Date(),
            source: 'app',
            breakStartSelfie: breakStartSelfie || '',
            breakStartLocation: buildBreakLocation(req.body)
        });

        const breakStartAddress = buildAddressString(
            doc.breakStartLocation?.address,
            doc.breakStartLocation?.area,
            doc.breakStartLocation?.city,
            doc.breakStartLocation?.pincode
        );
        await createBreakLog({
            breakDoc: doc,
            action: 'BREAK_START',
            performedBy: req.user?._id || staff.userId || staff._id,
            performedByName: req.user?.name || staff.name,
            performedByEmail: req.user?.email || staff.email,
            selfieUrl: breakStartSelfie,
            timestamp: doc.startTime,
            startAddress: breakStartAddress,
            startLocation: doc.breakStartLocation || {},
            payload: {
                breakId: doc._id,
                employeeID: doc.employeeID,
                tenantId: doc.tenantId,
                deviceId: doc.deviceId,
                source: doc.source,
                startTime: doc.startTime,
                endTime: doc.endTime,
                totalSeconds: doc.totalSeconds,
                breakStartSelfie: doc.breakStartSelfie || '',
                breakEndSelfie: doc.breakEndSelfie || '',
                breakStartLocation: doc.breakStartLocation || {},
                breakEndLocation: doc.breakEndLocation || {}
            }
        });

        await Staff.updateOne({ _id: staff._id }, { $set: { monitoringStatus: 'break' } });

        return res.status(201).json({
            success: true,
            message: 'Break started successfully',
            data: serializeBreak(doc)
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};

exports.endBreak = async (req, res) => {
    try {
        const { id } = req.params;
        const { latitude, longitude, selfie, endTime } = req.body;
        if (!req.staff?._id) {
            return res.status(404).json({ success: false, message: 'Staff record not found' });
        }
        if (latitude === undefined || longitude === undefined) {
            return res.status(400).json({ success: false, message: 'Location coordinates are missing' });
        }
        if (!selfie) {
            return res.status(400).json({ success: false, message: 'Break end selfie is required' });
        }

        const staff = await Staff.findById(req.staff._id).select('_id businessId name email userId');
        if (!staff?.businessId) {
            return res.status(404).json({ success: false, message: 'Staff business not found' });
        }

        const doc = await Break.findOne({
            _id: id,
            employeeID: staff._id,
            tenantId: staff.businessId,
            endTime: null
        });

        if (!doc) {
            return res.status(404).json({ success: false, message: 'Break not found or already ended' });
        }

        const breakEndSelfie = await uploadBreakSelfie(
            selfie,
            req,
            String(staff.businessId),
            staff.name,
            'break-end'
        );

        const resolvedEndTime = endTime ? new Date(endTime) : new Date();
        const totalSeconds = Math.max(
            0,
            Math.floor((resolvedEndTime.getTime() - new Date(doc.startTime).getTime()) / 1000)
        );

        doc.endTime = resolvedEndTime;
        doc.totalSeconds = totalSeconds;
        doc.breakEndSelfie = breakEndSelfie || '';
        doc.breakEndLocation = buildBreakLocation(req.body);
        await doc.save();

        const breakEndAddress = buildAddressString(
            doc.breakEndLocation?.address,
            doc.breakEndLocation?.area,
            doc.breakEndLocation?.city,
            doc.breakEndLocation?.pincode
        );
        const breakStartAddress = buildAddressString(
            doc.breakStartLocation?.address,
            doc.breakStartLocation?.area,
            doc.breakStartLocation?.city,
            doc.breakStartLocation?.pincode
        );
        await createBreakLog({
            breakDoc: doc,
            action: 'BREAK_END',
            performedBy: req.user?._id || staff.userId || staff._id,
            performedByName: req.user?.name || staff.name,
            performedByEmail: req.user?.email || staff.email,
            selfieUrl: breakEndSelfie,
            timestamp: doc.endTime,
            startAddress: breakStartAddress,
            endAddress: breakEndAddress,
            startLocation: doc.breakStartLocation || {},
            endLocation: doc.breakEndLocation || {},
            totalSeconds,
            payload: {
                breakId: doc._id,
                employeeID: doc.employeeID,
                tenantId: doc.tenantId,
                deviceId: doc.deviceId,
                source: doc.source,
                startTime: doc.startTime,
                endTime: doc.endTime,
                totalSeconds: doc.totalSeconds,
                breakStartSelfie: doc.breakStartSelfie || '',
                breakEndSelfie: doc.breakEndSelfie || '',
                breakStartLocation: doc.breakStartLocation || {},
                breakEndLocation: doc.breakEndLocation || {}
            }
        });

        await Staff.updateOne({ _id: staff._id }, { $set: { monitoringStatus: 'active' } });
        if (doc.deviceId) {
            await Device.updateOne(
                { deviceId: doc.deviceId },
                { $set: { status: 'active', lastSeenAt: new Date() } }
            );
        }

        return res.status(200).json({
            success: true,
            message: 'Break ended successfully',
            data: serializeBreak(doc)
        });
    } catch (error) {
        return res.status(500).json({ success: false, message: error.message });
    }
};
