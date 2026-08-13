require('dotenv').config({ path: require('path').join(__dirname, '../../.env') });
const mongoose = require('mongoose');
const connectDB = require('../config/db');
const Staff = require('../models/Staff');
const Attendance = require('../models/Attendance');

const updateAttendancePunchIn = async () => {
    try {
        // Connect to database
        await connectDB();
        console.log('Connected to database');
        console.log('Database Name:', mongoose.connection.db?.databaseName || 'Unknown');

        // CHANGE THIS EMAIL WHEN YOU WANT TO UPDATE ANOTHER STAFF
        const email = 'boominathanaskeva@gmail.com';
        const newPunchInTime = '10:05'; // 10:05 AM
        const targetDate = new Date('2026-01-28'); // Based on the punchIn date in the document

        console.log('\n=== Updating Attendance Punch-In Time ===');
        console.log('Email:', email);
        console.log('New Punch-In Time:', newPunchInTime);
        console.log('Target Date:', targetDate.toISOString().split('T')[0]);

        // Find Staff by email
        const staff = await Staff.findOne({ email: email.toLowerCase().trim() });
        
        if (!staff) {
            console.log('❌ Staff not found with email:', email);
            process.exit(1);
        }

        console.log('✅ Staff found!');
        console.log('Staff ID:', staff._id);
        console.log('Name:', staff.name);
        console.log('Employee ID:', staff.employeeId);

        // Find attendance record
        // The date field should be the start of the day (00:00:00)
        const startOfDay = new Date(targetDate);
        startOfDay.setHours(0, 0, 0, 0);
        const endOfDay = new Date(targetDate);
        endOfDay.setHours(23, 59, 59, 999);

        console.log('\nSearching for attendance record...');
        console.log('Date range:', startOfDay.toISOString(), 'to', endOfDay.toISOString());

        // Try to find by employeeId first
        let attendance = await Attendance.findOne({
            employeeId: staff._id,
            date: { $gte: startOfDay, $lte: endOfDay }
        });

        // If not found, try by user field
        if (!attendance) {
            attendance = await Attendance.findOne({
                user: staff._id,
                date: { $gte: startOfDay, $lte: endOfDay }
            });
        }

        if (!attendance) {
            console.log('❌ Attendance record not found for date:', targetDate.toISOString().split('T')[0]);
            console.log('Creating new attendance record...');
            
            // Create new attendance record
            const [hours, minutes] = newPunchInTime.split(':').map(Number);
            const punchInDateTime = new Date(targetDate);
            punchInDateTime.setHours(hours, minutes, 0, 0);

            attendance = await Attendance.create({
                employeeId: staff._id,
                user: staff._id,
                businessId: staff.businessId,
                date: startOfDay,
                punchIn: punchInDateTime,
                status: 'Pending',
            });

            console.log('✅ Created new attendance record');
        } else {
            console.log('✅ Attendance record found!');
            console.log('Current Punch-In:', attendance.punchIn);
            
            // Update punch-in time
            const [hours, minutes] = newPunchInTime.split(':').map(Number);
            const punchInDateTime = new Date(targetDate);
            punchInDateTime.setHours(hours, minutes, 0, 0);

            attendance.punchIn = punchInDateTime;
            await attendance.save();

            console.log('✅ Updated punch-in time to:', punchInDateTime.toISOString());
            console.log('Local time:', punchInDateTime.toLocaleString('en-IN', { timeZone: 'Asia/Kolkata' }));
        }

        // Display updated record
        const updatedAttendance = await Attendance.findById(attendance._id);
        console.log('\n=== Updated Attendance Record ===');
        console.log('ID:', updatedAttendance._id);
        console.log('Date:', updatedAttendance.date);
        console.log('Punch-In:', updatedAttendance.punchIn);
        console.log('Punch-In (Local IST):', updatedAttendance.punchIn.toLocaleString('en-IN', { timeZone: 'Asia/Kolkata' }));
        console.log('Status:', updatedAttendance.status);

        process.exit(0);
    } catch (error) {
        console.error('❌ Error:', error.message);
        console.error('Stack:', error.stack);
        process.exit(1);
    }
};

// Run the script
updateAttendancePunchIn();
