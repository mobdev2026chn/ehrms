/**
 * Attendance Auto-Mark Service
 * Marks "Not Marked" attendance as "Absent" for past days. Creates absent records for missing employees.
 * Excludes Sundays and holidays.
 */
const Attendance = require('../models/Attendance');
const Staff = require('../models/Staff');
const { getHolidayTemplateForStaff, getHolidayForDate } = require('../utils/holidayTemplateHelper');

function isSunday(date) {
    return date.getDay() === 0;
}

function getHolidayCacheKey(staff) {
    if (staff?.holidayTemplateId) {
        const templateId = staff.holidayTemplateId._id || staff.holidayTemplateId;
        return `template:${String(templateId)}`;
    }
    if (staff?.businessId) {
        return `business:${String(staff.businessId)}`;
    }
    if (staff?._id) {
        return `staff:${String(staff._id)}`;
    }
    return 'unknown';
}

async function isHolidayForStaff(date, staff, templateCache) {
    if (!staff?.businessId && !staff?.holidayTemplateId) return false;
    try {
        const cacheKey = getHolidayCacheKey(staff);
        let template = templateCache.get(cacheKey);

        if (template === undefined) {
            template = await getHolidayTemplateForStaff(staff);
            templateCache.set(cacheKey, template || null);
        }

        return !!getHolidayForDate(template, date);
    } catch (e) {
        console.error('[AttendanceAutoMark] isHolidayForStaff error:', e.message);
        return false;
    }
}

async function autoMarkPastAttendance() {
    let updatedCount = 0;
    let skippedCount = 0;
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const startOfMonth = new Date(today.getFullYear(), today.getMonth(), 1);
    startOfMonth.setHours(0, 0, 0, 0);
    const holidayTemplateCache = new Map();

    try {
        const notMarkedRecords = await Attendance.find({
            status: 'Not Marked',
            date: { $gte: startOfMonth, $lt: today },
        })
            .populate('employeeId', 'businessId holidayTemplateId')
            .lean();

        for (const record of notMarkedRecords) {
            const recordDate = new Date(record.date);
            recordDate.setHours(0, 0, 0, 0);
            if (isSunday(recordDate)) {
                skippedCount++;
                continue;
            }
            const holidayStaff = {
                _id: record.employeeId?._id || record.employeeId,
                businessId: record.businessId || record.employeeId?.businessId,
                holidayTemplateId: record.employeeId?.holidayTemplateId
            };
            if (await isHolidayForStaff(recordDate, holidayStaff, holidayTemplateCache)) {
                skippedCount++;
                continue;
            }
            const res = await Attendance.updateOne(
                { _id: record._id },
                { $set: { status: 'Absent', remarks: 'Auto-marked as Absent - no punch in/out recorded' } }
            );
            if (res.modifiedCount > 0) updatedCount++;
        }

        const daysToProcess = [];
        let curr = new Date(startOfMonth);
        while (curr < today) {
            daysToProcess.push(new Date(curr));
            curr.setDate(curr.getDate() + 1);
        }

        const allActiveStaff = await Staff.find({ status: 'Active' })
            .select('_id businessId joiningDate holidayTemplateId')
            .lean();

        for (const processDate of daysToProcess) {
            if (isSunday(processDate)) {
                skippedCount++;
                continue;
            }
            const dateStart = new Date(processDate);
            dateStart.setHours(0, 0, 0, 0);
            const dateEnd = new Date(processDate);
            dateEnd.setHours(23, 59, 59, 999);

            const eligible = allActiveStaff.filter((emp) => {
                if (!emp.joiningDate) return true;
                const jd = new Date(emp.joiningDate);
                jd.setHours(0, 0, 0, 0);
                return jd <= processDate;
            });
            if (eligible.length === 0) continue;

            const ids = eligible.map((e) => e._id);
            const existing = await Attendance.find({
                employeeId: { $in: ids },
                date: { $gte: dateStart, $lte: dateEnd },
            })
                .select('employeeId')
                .lean();
            const existingIds = new Set(existing.map((a) => (a.employeeId && a.employeeId.toString()) || String(a.employeeId)));
            const missing = eligible.filter((e) => !existingIds.has(e._id.toString()));

            if (missing.length > 0) {
                const batch = [];
                for (const emp of missing) {
                    if (await isHolidayForStaff(processDate, emp, holidayTemplateCache)) {
                        skippedCount++;
                        continue;
                    }

                    batch.push({
                        employeeId: emp._id,
                        date: dateStart,
                        status: 'Absent',
                        remarks: `Auto-marked as Absent - no punch in/out recorded for ${processDate.toISOString().split('T')[0]}`,
                        businessId: emp.businessId || undefined,
                    });
                }

                if (batch.length === 0) {
                    continue;
                }

                try {
                    await Attendance.insertMany(batch, { ordered: false });
                    updatedCount += batch.length;
                } catch (err) {
                    if (err.code === 11000) {
                        const inserted = batch.length - (err.writeErrors?.length || 0);
                        updatedCount += Math.max(0, inserted);
                    } else throw err;
                }
            }
        }

        if (updatedCount > 0 || skippedCount > 0) {
            console.log('[AttendanceAutoMark] Completed: updated=', updatedCount, 'skipped=', skippedCount);
        }
        return { updatedCount, skippedCount };
    } catch (e) {
        console.error('[AttendanceAutoMark] Error:', e.message);
        return { updatedCount, skippedCount };
    }
}

module.exports = { autoMarkPastAttendance };
