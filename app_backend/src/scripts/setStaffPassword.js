const dns = require('dns');
try {
    dns.setDefaultResultOrder('ipv4first');
    dns.setServers(['8.8.8.8', '8.8.4.4', '1.1.1.1']);
} catch (e) {}
require('dotenv').config({ path: 'd:/Projects/ektaHr/ehrms-main/ehrms-main/ektahr_desktop/monitoring_backend/.env' });
const mongoose = require('mongoose');
const connectDB = require('../config/db');
const User = require('../models/User');

const setAdminPassword = async () => {
    try {
        await connectDB();
        console.log('Connected to database:', mongoose.connection.db?.databaseName);

        const email = 'sachin@gmail.com';
        const newPassword = '#India123';

        console.log(`Searching for User with email: ${email}...`);
        let user = await User.findOne({ email: email.toLowerCase().trim() });

        if (!user) {
            console.log(`User ${email} not found in User collection. Searching all admin users...`);
            user = await User.findOne({ role: 'Admin' });
        }

        if (!user) {
            console.log('❌ No Admin user found!');
            process.exit(1);
        }

        console.log('✅ Admin user found:', user.email, '| Name:', user.name);

        user.password = newPassword;
        await user.save();

        console.log(`\n🎉 Password for ${user.email} updated successfully to: ${newPassword}`);
        process.exit(0);
    } catch (e) {
        console.error('Error:', e.message);
        process.exit(1);
    }
};

setAdminPassword();
