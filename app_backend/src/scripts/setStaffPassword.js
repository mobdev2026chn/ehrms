require('dotenv').config({ path: require('path').join(__dirname, '../../.env') });
const mongoose = require('mongoose');
const connectDB = require('../config/db');
const Staff = require('../models/Staff');

const setStaffPassword = async () => {
    try {
        // Connect to database
        await connectDB();
        console.log('Connected to database');
        console.log('Database Name:', mongoose.connection.db?.databaseName || 'Unknown');

        const email = 'suganthi0623@gmail.com';
        const newPassword = '#India123';

        console.log('\n=== Setting Staff Password ===');
        console.log('Email:', email);
        console.log('New Password:', newPassword);

        // Find Staff
        const staff = await Staff.findOne({ email: email.toLowerCase().trim() });
        
        if (!staff) {
            console.log('❌ Staff not found with email:', email);
            process.exit(1);
        }

        console.log('✅ Staff found!');
        console.log('Staff ID:', staff._id);
        console.log('Name:', staff.name);
        console.log('Employee ID:', staff.employeeId);
        console.log('Current Password Set:', staff.password ? 'Yes' : 'No');

        // Set password (will be hashed automatically by pre-save hook)
        staff.password = newPassword;
        await staff.save();

        console.log('\n✅ Password set successfully!');

        // Verify password by reloading and testing
        const updatedStaff = await Staff.findById(staff._id).select('+password');
        const passwordMatch = await updatedStaff.matchPassword(newPassword);
        
        console.log('Password verification:', passwordMatch ? '✅ CORRECT' : '❌ INCORRECT');
        
        if (passwordMatch) {
            console.log('\n✅ Staff can now login with:');
            console.log('  Email:', email);
            console.log('  Password:', newPassword);
        }

        process.exit(0);
    } catch (error) {
        console.error('❌ Error:', error.message);
        console.error('Stack:', error.stack);
        process.exit(1);
    }
};

setStaffPassword();
