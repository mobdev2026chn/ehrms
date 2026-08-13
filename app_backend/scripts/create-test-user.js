/**
 * Creates a test Admin user + linked Staff record for local development login.
 * Usage: node scripts/create-test-user.js
 */
require('dotenv').config();
const mongoose = require('mongoose');
const bcrypt = require('bcrypt');

const MONGO_URI = process.env.MONGODB_URI;
const EMAIL    = process.env.SEED_EMAIL    || 'boomi@gmail.com';
const PASSWORD = process.env.SEED_PASSWORD || 'Test@1234';
const NAME     = process.env.SEED_NAME     || 'Boominathan';

async function main() {
    await mongoose.connect(MONGO_URI);
    console.log('Connected to MongoDB:', mongoose.connection.host);

    const User  = require('../src/models/User');
    const Staff = require('../src/models/Staff');

    // --- User ---
    let user = await User.findOne({ email: EMAIL });
    if (user) {
        console.log(`User already exists: ${user._id}`);
    } else {
        user = await User.create({
            name:     NAME,
            email:    EMAIL,
            password: PASSWORD,   // hashed by pre-save hook
            role:     'Admin',
            isActive: true,
        });
        console.log(`Created User: ${user._id}`);
    }

    // --- Staff ---
    let staff = await Staff.findOne({ email: EMAIL });
    if (staff) {
        // Link to user if not already linked
        if (!staff.userId || String(staff.userId) !== String(user._id)) {
            staff.userId = user._id;
            await staff.save();
            console.log(`Updated Staff userId link: ${staff._id}`);
        } else {
            console.log(`Staff already exists and linked: ${staff._id}`);
        }
    } else {
        // Generate a short unique employeeId
        const empId = 'EMP-' + Date.now().toString().slice(-6);
        staff = await Staff.create({
            employeeId:  empId,
            userId:      user._id,
            name:        NAME,
            email:       EMAIL,
            password:    PASSWORD,  // hashed by pre-save hook
            designation: 'Administrator',
            department:  'Management',
            status:      'Active',
            staffType:   'Full Time',
        });
        console.log(`Created Staff: ${staff._id}  (employeeId: ${empId})`);
    }

    console.log('\n✅ Done!');
    console.log(`   Email   : ${EMAIL}`);
    console.log(`   Password: ${PASSWORD}`);
    console.log('   You can now log in with these credentials.\n');

    await mongoose.disconnect();
}

main().catch(err => {
    console.error('❌ Error:', err.message);
    process.exit(1);
});
