require('dotenv').config();
const mongoose = require('mongoose');
const Staff = require('./src/models/Staff');
const Company = require('./src/models/Company');
const Leave = require('./src/models/Leave');
const Attendance = require('./src/models/Attendance');

(async () => {
    await mongoose.connect(process.env.MONGODB_URI);
    console.log('Connected to', mongoose.connection.name);

    const email = 'askevaaiattendanceapp@gmail.com';
    const staff = await Staff.findOne({ email }).lean();
    if (!staff) {
        console.log('Staff not found for', email);
        process.exit(0);
    }
    console.log('Staff:', { id: staff._id, name: staff.name || staff.fullName, companyId: staff.companyId, shiftId: staff.shiftId, joiningDate: staff.joiningDate });

    const company = await Company.findById(staff.companyId).lean();
    console.log('Company:', company?.name);
    const shifts = company?.settings?.attendance?.shifts || [];
    console.log('Shifts count:', shifts.length);
    for (const s of shifts) {
        console.log('--- Shift ---', {
            _id: s._id,
            name: s.name,
            shiftType: s.shiftType,
            startTime: s.startTime,
            endTime: s.endTime,
            halfDaySettings: s.halfDaySettings,
        });
    }

    const now = new Date();
    const startOfDay = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate(), 0, 0, 0));
    const endOfDay = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate(), 23, 59, 59, 999));

    const leaves = await Leave.find({
        employeeId: staff._id,
        startDate: { $lte: endOfDay },
        endDate: { $gte: startOfDay }
    }).lean();
    console.log('Leaves overlapping today:', JSON.stringify(leaves, null, 2));

    const attendance = await Attendance.findOne({ employeeId: staff._id, date: startOfDay }).lean();
    console.log('Attendance today:', JSON.stringify(attendance, null, 2));

    process.exit(0);
})().catch(e => { console.error(e); process.exit(1); });
