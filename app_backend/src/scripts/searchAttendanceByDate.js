/**
 * Search attendance records for a specific date (Mongo format).
 * Usage: node src/scripts/searchAttendanceByDate.js
 * Edit the TARGET_DATE below to search another date.
 */
require('dotenv').config();
const mongoose = require('mongoose');
const connectDB = require('../config/db');
const Attendance = require('../models/Attendance');
const Staff = require('../models/Staff');

// Target date: 02-Feb-2026 (edit year, monthIndex 0-based, day as needed)
const TARGET_YEAR = 2026;
const TARGET_MONTH = 2;   // February (1-based for display)
const TARGET_DAY = 2;

// MongoDB date range for the full day (any timezone)
const startOfDay = new Date(TARGET_YEAR, TARGET_MONTH - 1, TARGET_DAY, 0, 0, 0, 0);
const endOfDay = new Date(TARGET_YEAR, TARGET_MONTH - 1, TARGET_DAY, 23, 59, 59, 999);

console.log('\n--- MongoDB date search (use this in Compass / shell) ---');
console.log('Date range for', `${String(TARGET_DAY).padStart(2, '0')}-${String(TARGET_MONTH).padStart(2, '0')}-${TARGET_YEAR}:`);
console.log('  $gte:', startOfDay.toISOString());
console.log('  $lte:', endOfDay.toISOString());
console.log('\nMongo shell / Compass filter (paste as JSON):');
console.log(JSON.stringify({
    date: {
        $gte: { $date: startOfDay.toISOString() },
        $lte: { $date: endOfDay.toISOString() }
    }
}, null, 2));
console.log('\n--- Searching attendances collection ---\n');

async function run() {
    try {
        await connectDB();

        const records = await Attendance.find({
            date: { $gte: startOfDay, $lte: endOfDay }
        })
            .sort({ date: 1 })
            .lean();

        if (records.length === 0) {
            console.log('No attendance record found for', `${String(TARGET_DAY).padStart(2, '0')}-${String(TARGET_MONTH).padStart(2, '0')}-${TARGET_YEAR}.`);
            console.log('Total records in collection (any date):', await Attendance.countDocuments());
            return;
        }

        console.log('Found', records.length, 'record(s) for', `${String(TARGET_DAY).padStart(2, '0')}-${String(TARGET_MONTH).padStart(2, '0')}-${TARGET_YEAR}:\n`);

        for (let i = 0; i < records.length; i++) {
            const r = records[i];
            let staffName = '(unknown)';
            if (r.employeeId) {
                const staff = await Staff.findById(r.employeeId).select('name email').lean();
                if (staff) staffName = staff.name || staff.email || r.employeeId.toString();
            }
            console.log('--- Record', i + 1, '---');
            console.log('  _id:           ', r._id.toString());
            console.log('  date (stored): ', r.date);
            console.log('  date (ISO):    ', r.date instanceof Date ? r.date.toISOString() : r.date);
            console.log('  status:        ', r.status);
            console.log('  employeeId:    ', r.employeeId);
            console.log('  staff name:    ', staffName);
            console.log('  punchIn:       ', r.punchIn ?? 'null');
            console.log('  punchOut:      ', r.punchOut ?? 'null');
            console.log('  leaveType:     ', r.leaveType ?? 'null');
            console.log('');
        }

    } catch (err) {
        console.error('Error:', err.message);
    } finally {
        await mongoose.connection.close();
        process.exit(0);
    }
}

run();
