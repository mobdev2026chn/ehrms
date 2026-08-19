require('dotenv').config();
const mongoose = require('mongoose');
const connectDB = require('../config/db');
const Staff = require('../models/Staff');
const Attendance = require('../models/Attendance');
const Leave = require('../models/Leave');

async function fetchUserDocs() {
    try {
        await connectDB();
        const email = 'jashim.askeva@gmail.com';
        console.log(`\n--- Searching for Staff: ${email} ---`);
        
        const staff = await Staff.findOne({ email }).select('name email employeeId businessId');
        if (!staff) {
            console.log('Staff record not found.');
            return;
        }
        console.log('Staff Document:', JSON.stringify(staff, null, 2));

        const targetDate = new Date(2026, 0, 31); // Jan 31, 2026
        const startOfDay = new Date(2026, 0, 31, 0, 0, 0, 0);
        const endOfDay = new Date(2026, 0, 31, 23, 59, 59, 999);

        console.log(`\n--- Searching for Attendance on Jan 31, 2026 ---`);
        const attendance = await Attendance.find({
            $or: [{ employeeId: staff._id }, { user: staff._id }],
            date: { $gte: startOfDay, $lte: endOfDay }
        });
        console.log(`Found ${attendance.length} record(s):`);
        console.log(JSON.stringify(attendance, null, 2));

        console.log(`\n--- Searching for ALL Leave Records for this user ---`);
        const leaves = await Leave.find({ employeeId: staff._id });
        console.log(`Found ${leaves.length} leave record(s):`);
        console.log(JSON.stringify(leaves, null, 2));

        console.log(`\n--- Searching for Approved Leaves covering Jan 31, 2026 ---`);
        const activeLeaves = await Leave.find({
            employeeId: staff._id,
            status: 'Approved',
            startDate: { $lte: endOfDay },
            endDate: { $gte: startOfDay }
        });
        console.log(`Found ${activeLeaves.length} approved leave(s):`);
        console.log(JSON.stringify(activeLeaves, null, 2));

    } catch (error) {
        console.error('Error:', error);
    } finally {
        await mongoose.connection.close();
    }
}

fetchUserDocs();
