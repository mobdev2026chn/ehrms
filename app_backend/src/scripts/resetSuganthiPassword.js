require('dotenv').config({ path: require('path').join(__dirname, '../../.env') });
const connectDB = require('../config/db');
const User = require('../models/User');
const Staff = require('../models/Staff');

const resetSuganthiPassword = async () => {
    try {
        // Connect to database
        await connectDB();
        console.log('Connected to database');
        console.log('Database Name:', mongoose.connection.db?.databaseName || 'Unknown');

        const email = 'suganthi0623m@gmail.com';
        const newPassword = 'Suganthi@123'; // Set a known password

        console.log('\n=== Resetting Password for Suganthi ===');
        console.log('Email:', email);
        console.log('New Password:', newPassword);

        // Find User
        const user = await User.findOne({ email: email.toLowerCase().trim() });
        
        if (!user) {
            console.log('❌ User not found with email:', email);
            console.log('Creating new User...');
            
            // Check if Staff exists to get details
            const staff = await Staff.findOne({ email: email.toLowerCase().trim() });
            
            if (staff) {
                // Create User linked to Staff
                const newUser = await User.create({
                    name: staff.name,
                    email: staff.email,
                    password: newPassword,
                    role: 'Employee',
                    isActive: true,
                    companyId: staff.businessId,
                    branchId: staff.branchId
                });
                
                // Update Staff with userId
                staff.userId = newUser._id;
                await staff.save();
                
                console.log('✅ User created and linked to Staff!');
                console.log('User ID:', newUser._id);
            } else {
                console.log('❌ Staff also not found. Cannot create User.');
                process.exit(1);
            }
        } else {
            console.log('✅ User found!');
            console.log('User ID:', user._id);
            console.log('Current Role:', user.role);
            
            // Reset password
            user.password = newPassword;
            await user.save();
            
            console.log('✅ Password reset successfully!');
            console.log('New password:', newPassword);
            
            // Verify password
            const passwordMatch = await user.matchPassword(newPassword);
            console.log('Password verification:', passwordMatch ? '✅ CORRECT' : '❌ INCORRECT');
        }

        // Verify Staff link
        const staff = await Staff.findOne({ email: email.toLowerCase().trim() });
        if (staff) {
            const linkedUser = await User.findById(staff.userId || user._id);
            console.log('\n=== Staff-User Link ===');
            console.log('Staff ID:', staff._id);
            console.log('Staff User ID:', staff.userId);
            console.log('Linked User:', linkedUser ? '✅ Yes' : '❌ No');
        }

        console.log('\n✅ Password reset complete!');
        console.log('Login credentials:');
        console.log('  Email:', email);
        console.log('  Password:', newPassword);

        process.exit(0);
    } catch (error) {
        console.error('❌ Error:', error.message);
        console.error('Stack:', error.stack);
        process.exit(1);
    }
};

const mongoose = require('mongoose');
resetSuganthiPassword();
