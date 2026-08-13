/**
 * Maps logged-in staff ID to their Feb 02 2026 attendance record.
 * The app only returns attendance where employeeId (or user) = req.staff._id (logged-in staff).
 *
 * Usage: node src/scripts/checkFeb02RecordByStaffId.js [staffId]
 *   With no arg: print table of all 6 staff and their Feb 02 record.
 *   With staffId: print only that staff's Feb 02 record (what the app shows when they're logged in).
 */
require('dotenv').config();
const mongoose = require('mongoose');
const connectDB = require('../config/db');
const Attendance = require('../models/Attendance');
const Staff = require('../models/Staff');

const FEB02_START = new Date(2026, 1, 2, 0, 0, 0, 0);
const FEB02_END = new Date(2026, 1, 2, 23, 59, 59, 999);

async function run() {
    const staffIdArg = process.argv[2]; // optional staff ID to check

    try {
        await connectDB();

        const records = await Attendance.find({
            date: { $gte: FEB02_START, $lte: FEB02_END }
        }).sort({ date: 1 }).lean();

        if (records.length === 0) {
            console.log('No attendance records for 02-Feb-2026.');
            return;
        }

        // Resolve staff names
        const staffIds = [...new Set(records.map(r => r.employeeId?.toString()).filter(Boolean))];
        const staffMap = {};
        for (const id of staffIds) {
            const s = await Staff.findById(id).select('name email').lean();
            staffMap[id] = s ? (s.name || s.email || id) : id;
        }

        console.log('\n=== Feb 02 2026: Staff ID → Record (what app shows when that staff is logged in) ===\n');
        console.log('Backend filters month attendance by: employeeId or user = req.staff._id (logged-in staff).');
        console.log('So each staff sees only their own row for Feb 02 2026.\n');

        const table = [];
        for (const r of records) {
            const eid = r.employeeId?.toString() || '';
            const name = staffMap[eid] || '(no staff found)';
            table.push({
                staffName: name,
                staffId: eid,
                attendanceId: r._id.toString(),
                status: r.status,
                punchIn: r.punchIn ? new Date(r.punchIn).toISOString() : null,
                punchOut: r.punchOut ? new Date(r.punchOut).toISOString() : null
            });
        }

        if (staffIdArg) {
            const id = staffIdArg.trim();
            const match = table.find(t =>
                t.staffId === id ||
                t.staffId.toLowerCase() === id.toLowerCase()
            );
            if (match) {
                console.log('Logged-in staff ID:', id);
                console.log('Feb 02 2026 record for this staff:');
                console.log('  Staff name:    ', match.staffName);
                console.log('  Staff _id:     ', match.staffId);
                console.log('  Status:        ', match.status);
                console.log('  Attendance _id:', match.attendanceId);
                console.log('  PunchIn:       ', match.punchIn ?? 'null');
                console.log('  PunchOut:      ', match.punchOut ?? 'null');
            } else {
                console.log('No Feb 02 2026 record found for staff ID:', id);
                console.log('Staff IDs that have a Feb 02 2026 record:');
                table.forEach(t => console.log('  ', t.staffId, ' ', t.staffName));
            }
        } else {
            console.log('Staff name      | Staff _id (logged-in)     | Status   | Attendance _id');
            console.log('----------------|---------------------------|----------|------------------');
            for (const t of table) {
                const name = (t.staffName + ' (record)').slice(0, 14).padEnd(14);
                const sid = (t.staffId || '').slice(0, 25).padEnd(25);
                const st = (t.status || '').padEnd(8);
                const aid = (t.attendanceId || '').slice(0, 18);
                console.log(`${name} | ${sid} | ${st} | ${aid}`);
            }
            console.log('\nWhen a user logs in, JWT carries user._id → backend resolves req.staff._id.');
            console.log('Month attendance returns only rows where employeeId = req.staff._id.');
            console.log('So "Staff _id" above is who sees that row; "Status" is what they see for Feb 02.');
        }

    } catch (err) {
        console.error('Error:', err.message);
    } finally {
        await mongoose.connection.close();
        process.exit(0);
    }
}

run();
