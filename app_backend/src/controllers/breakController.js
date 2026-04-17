const Break = require('../models/Break');
const Device = require('../models/Device');
const Staff = require('../models/Staff');
const Company = require('../models/Company');
const Attendance = require('../models/Attendance');
const AttendanceLog = require('../models/AttendanceLog');
const digitalOceanService = require('../services/digitalOceanService');
const { getEffectiveFineConfig, calculateFineAmount } = require('../utils/fineCalculationHelper');
const { getShiftTimings, calculateWorkHoursFromShift } = require('../utils/leaveAttendanceHelper');

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
        breakMin: doc.breakMin ?? 0,
        breakCount: doc.breakCount ?? 0,
        breakFineMins: doc.breakFineMins ?? 0,
        breakFineAmount: doc.breakFineAmount ?? 0,
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
    attendanceId,
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
    breakSummary,
    payload
}) {
    if (!breakDoc?._id || !performedBy) return;
    const logPayload = {
        // Use the day's attendance _id so attendance detail can fetch break logs.
        attendanceId: attendanceId || breakDoc._id,
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
        if (breakSummary) {
            logPayload.break = breakSummary;
        }
    }

    await AttendanceLog.create(logPayload)
        .catch(err => console.warn(`[AttendanceLog] ${action} create failed:`, err?.message));
}

async function getAttendanceIdForDate(employeeId, eventDate) {
    if (!employeeId || !eventDate) return null;
    const dt = new Date(eventDate);
    if (Number.isNaN(dt.getTime())) return null;
    const dayStart = new Date(Date.UTC(
        dt.getUTCFullYear(),
        dt.getUTCMonth(),
        dt.getUTCDate()
    ));
    const dayEnd = new Date(dayStart);
    dayEnd.setUTCDate(dayEnd.getUTCDate() + 1);
    const attendanceDoc = await Attendance.findOne({
        employeeId,
        date: { $gte: dayStart, $lt: dayEnd }
    }).select('_id').lean();
    return attendanceDoc?._id || null;
}

function calculateSalaryStructure(salary = {}) {
    const grossSalary =
        (salary.basicSalary || 0)
        + (salary.dearnessAllowance || 0)
        + (salary.houseRentAllowance || 0)
        + (salary.specialAllowance || 0);
    const employeePF = grossSalary * ((salary.employeePFRate || 0) / 100);
    const employeeESI = grossSalary * ((salary.employeeESIRate || 0) / 100);
    const netMonthlySalary = grossSalary - employeePF - employeeESI;
    return { monthly: { grossSalary, netMonthlySalary } };
}

function resolveBreakDurationMinutes(breakDoc) {
    if (Number.isFinite(Number(breakDoc?.totalSeconds)) && Number(breakDoc.totalSeconds) >= 0) {
        return Math.max(0, Math.round(Number(breakDoc.totalSeconds) / 60));
    }
    const start = breakDoc?.startTime ? new Date(breakDoc.startTime).getTime() : null;
    const end = breakDoc?.endTime ? new Date(breakDoc.endTime).getTime() : null;
    if (!start || !end || end < start) return 0;
    return Math.max(0, Math.round((end - start) / (1000 * 60)));
}

async function getBreakFineContext(staff, dayDate) {
    const company = await Company.findById(staff.businessId)
        .select('settings.payroll.fineCalculation settings.attendance.shifts settings.business.timezone settings.attendance.timezone timezone')
        .lean();
    const payrollFineConfig = getEffectiveFineConfig(company || {});

    let dailyNet = Number(staff?.appPerDayNetSalary) || 0;
    let dailyGross = Number(staff?.appPerdayGrossSalary) || 0;
    if ((dailyNet <= 0 || dailyGross <= 0) && staff?.salary) {
        const salaryStructure = calculateSalaryStructure(staff.salary);
        const monthlyNet = Number(salaryStructure?.monthly?.netMonthlySalary) || 0;
        const monthlyGross = Number(salaryStructure?.monthly?.grossSalary) || 0;
        if (dailyNet <= 0 && monthlyNet > 0) dailyNet = monthlyNet / 30;
        if (dailyGross <= 0 && monthlyGross > 0) dailyGross = monthlyGross / 30;
    }
    if (dailyGross <= 0) dailyGross = dailyNet;

    const shiftTiming = getShiftTimings(company || {}, staff, dayDate, staff?.joiningDate || null, null);
    const shiftBreakPolicy = shiftTiming?.breakPolicy || {};
    const policyEnabled = shiftBreakPolicy?.enabled === true;
    const configuredAllowedBreakMin = Math.max(0, Number(shiftBreakPolicy?.allowedMinutes || 0));
    // Business rule:
    // - breakPolicy.enabled=false -> unrestricted break, no fine.
    // - breakPolicy.allowedMinutes=0 -> unrestricted break, no fine.
    const isUnlimitedBreak = !policyEnabled || configuredAllowedBreakMin === 0;
    const breakFineEnabled =
        policyEnabled &&
        !isUnlimitedBreak &&
        shiftBreakPolicy?.fineEnabled === true;
    const allowedBreakMin = isUnlimitedBreak ? Number.POSITIVE_INFINITY : configuredAllowedBreakMin;

    let fineConfig = payrollFineConfig;
    if (breakFineEnabled) {
        const fineType = String(shiftBreakPolicy?.fineType || '1xSalary');
        if (fineType === 'custom') {
            fineConfig = {
                enabled: true,
                calculationType: 'fixedPerHour',
                finePerHour: Math.max(0, Number(shiftBreakPolicy?.customFinePerHour || 0)),
                fineRules: []
            };
        } else {
            fineConfig = {
                enabled: true,
                calculationType: 'shiftBased',
                finePerHour: 0,
                fineRules: [{ type: fineType, applyTo: 'earlyExit' }]
            };
        }
    } else {
        fineConfig = { ...payrollFineConfig, enabled: false };
    }

    let shiftHours = 9;
    const shiftType = (shiftTiming?.shiftType || '').toString().toLowerCase();
    if (shiftType === 'open' || shiftType === 'open shift') {
        const openHours = Number(shiftTiming?.openWorkHours || shiftTiming?.workHours);
        if (Number.isFinite(openHours) && openHours > 0) shiftHours = openHours;
    } else {
        const fixedHours = calculateWorkHoursFromShift(shiftTiming?.startTime || '09:30', shiftTiming?.endTime || '18:30');
        if (Number.isFinite(fixedHours) && fixedHours > 0) shiftHours = fixedHours;
    }

    return {
        allowedBreakMin,
        fineConfig,
        breakPolicy: {
            enabled: policyEnabled,
            isUnlimitedBreak,
            allowedMinutes: configuredAllowedBreakMin,
            fineEnabled: breakFineEnabled,
            fineType: String(shiftBreakPolicy?.fineType || '1xSalary'),
            customFinePerHour: Math.max(0, Number(shiftBreakPolicy?.customFinePerHour || 0))
        },
        dailyNet,
        dailyGross,
        shiftHours
    };
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

        const staff = await Staff.findById(req.staff._id).select('_id businessId name email userId appPerDayNetSalary appPerdayGrossSalary salary joiningDate shiftId shiftName');
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
        const attendanceId = await getAttendanceIdForDate(staff._id, doc.startTime);
        await createBreakLog({
            attendanceId,
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

        const staff = await Staff.findById(req.staff._id).select('_id businessId name email userId appPerDayNetSalary appPerdayGrossSalary salary joiningDate shiftId shiftName');
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

        const dayStart = new Date(Date.UTC(
            resolvedEndTime.getUTCFullYear(),
            resolvedEndTime.getUTCMonth(),
            resolvedEndTime.getUTCDate()
        ));
        const dayEnd = new Date(dayStart);
        dayEnd.setUTCDate(dayEnd.getUTCDate() + 1);
        const attendanceDoc = await Attendance.findOne({
            employeeId: staff._id,
            date: { $gte: dayStart, $lt: dayEnd }
        }).select('break').lean();

        const previousTotalBreakMin = Number(attendanceDoc?.break?.totalBreakMin) || 0;
        const previousTotalFineAmount =
            Number(attendanceDoc?.break?.totalBreakFineAmount)
            || Number(attendanceDoc?.break?.breakFineAmount)
            || 0;
        const previousTotalFineMins =
            Number(attendanceDoc?.break?.totalBreakFineMins)
            || Number(attendanceDoc?.break?.breakFineMins)
            || 0;
        const previousTotalBreakCount = Number(attendanceDoc?.break?.totalBreakCount) || 0;
        const currentBreakMin = resolveBreakDurationMinutes(doc);

        const fineCtx = await getBreakFineContext(staff, resolvedEndTime);
        const totalBreakAfterCurrent = previousTotalBreakMin + currentBreakMin;
        const totalFineMinsAfterCurrent = Math.max(0, totalBreakAfterCurrent - fineCtx.allowedBreakMin);
        const currentBreakFineMins = Math.max(0, totalFineMinsAfterCurrent - Math.max(0, previousTotalFineMins));
        const currentBreakFineAmount = currentBreakFineMins > 0
            ? calculateFineAmount(
                currentBreakFineMins,
                'earlyExit',
                fineCtx.fineConfig,
                fineCtx.dailyNet,
                fineCtx.shiftHours,
                fineCtx.dailyGross
            )
            : 0;
        const totalFineAmountAfterCurrent = previousTotalFineAmount + currentBreakFineAmount;
        const breakTestTag = '[BreakFine][formula][test]';
        console.log(
            breakTestTag,
            'incremental | prevTotalBreakMin=',
            previousTotalBreakMin,
            '| currentBreakMin=',
            currentBreakMin,
            '| allowedBreakMin=',
            fineCtx.allowedBreakMin,
            '| currentBreakFineMins=',
            currentBreakFineMins,
            '| prevTotalFineAmount=',
            previousTotalFineAmount,
            '| currentBreakFineAmount=',
            currentBreakFineAmount,
            '| totalFineAmountAfterCurrent=',
            totalFineAmountAfterCurrent
        );

        doc.breakMin = currentBreakMin;
        doc.breakCount = previousTotalBreakCount + 1;
        doc.breakFineMins = currentBreakFineMins;
        doc.breakFineAmount = currentBreakFineAmount;
        await doc.save();
        await Attendance.updateOne(
            {
                employeeId: staff._id,
                date: { $gte: dayStart, $lt: dayEnd }
            },
            {
                $set: {
                    break: {
                        totalBreakMin: totalBreakAfterCurrent,
                        totalBreakCount: previousTotalBreakCount + 1,
                        totalBreakFineMins: totalFineMinsAfterCurrent,
                        totalBreakFineAmount: totalFineAmountAfterCurrent,
                        breaks: [
                            ...((attendanceDoc?.break?.breaks && Array.isArray(attendanceDoc.break.breaks)) ? attendanceDoc.break.breaks : []),
                            {
                                startTime: doc.startTime || null,
                                endTime: doc.endTime || null,
                                duration: currentBreakMin,
                                BreakCount: previousTotalBreakCount + 1,
                                breakFineMins: currentBreakFineMins,
                                breakFineAmount: currentBreakFineAmount
                            }
                        ]
                    }
                }
            }
        );

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
        const attendanceId = await getAttendanceIdForDate(staff._id, doc.endTime || resolvedEndTime);
        await createBreakLog({
            attendanceId,
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
            breakSummary: {
                BreakMin: currentBreakMin,
                breakFineMins: currentBreakFineMins,
                breakFineAmount: currentBreakFineAmount
            },
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
                breakEndLocation: doc.breakEndLocation || {},
                breakSummary: {
                    BreakMin: currentBreakMin,
                    breakFineMins: currentBreakFineMins,
                    breakFineAmount: currentBreakFineAmount
                },
                attendanceBreakTotals: {
                    totalBreakMin: totalBreakAfterCurrent,
                    totalBreakCount: previousTotalBreakCount + 1,
                    totalBreakFineMins: totalFineMinsAfterCurrent,
                    totalBreakFineAmount: totalFineAmountAfterCurrent
                }
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
