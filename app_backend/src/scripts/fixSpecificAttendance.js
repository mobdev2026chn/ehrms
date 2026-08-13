require('dotenv').config();
const mongoose = require('mongoose');
const connectDB = require('../config/db');
const Staff = require('../models/Staff');
const Attendance = require('../models/Attendance');

async function fixAttendanceRecord() {
    try {
        await connectDB();
        const email = 'jashim.askeva@gmail.com';
        
        const staff = await Staff.findOne({ email });
        if (!staff) {
            console.log('Staff record not found.');
            return;
        }

        const startOfDay = new Date(2026, 0, 31, 0, 0, 0, 0);
        const endOfDay = new Date(2026, 0, 31, 23, 59, 59, 999);

        console.log(`\n--- Fixing Attendance for Jan 31, 2026 ---`);
        
        // Find the record first to confirm
        const record = await Attendance.findOne({
            $or: [{ employeeId: staff._id }, { user: staff._id }],
            date: { $gte: startOfDay, $lte: endOfDay }
        });

        if (!record) {
            console.log('No attendance record found for this date.');
            return;
        }

        console.log(`Current Status: ${record.status}`);
        
        // Update the status to 'Present' (since they have a punchIn)
        // Or 'Pending' if your business logic requires approval. 
        // Based on the screenshot, it looks like they are marked as 'Late', 
        // so 'Present' is likely the correct state once the Half Day error is removed.
        record.status = 'Present'; 
        
        // Clear any half-day specific remarks if they exist
        if (record.remarks) {
            record.remarks = record.remarks.replace(/Half Day/i, '').trim();
        }

        await record.save();
        console.log(`Update successful. New Status: ${record.status}`);

    } catch (error) {
        console.error('Error:', error);
    } finally {
        await mongoose.connection.close();
    }
}

fixAttendanceRecord();
