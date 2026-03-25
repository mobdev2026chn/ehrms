/**
 * One-time script: insert Albino John user into users collection.
 * Uses native collection insert so the existing bcrypt password is not re-hashed.
 */
require('dotenv').config({ path: require('path').join(__dirname, '../../.env') });
const mongoose = require('mongoose');
const connectDB = require('../config/db');

const userDoc = {
  email: 'albinojohn@martellect.com',
  password: '$2a$10$v/xfPuGaGcSiRxNmR3ZEMOwTEq2ckzIN.PKCOyYDsX/wORDSt04LS',
  name: 'Albino John',
  role: 'Admin',
  phone: '6383583908',
  isActive: true,
  companyId: new mongoose.Types.ObjectId('69a5796e313bc36538d045ca'),
  hierarchyLevel: 0,
  sidebarPermissions: [],
  permissions: [],
  createdAt: new Date('2026-03-02T11:50:06.653Z'),
  updatedAt: new Date('2026-03-03T11:33:51.078Z'),
  lastLogin: new Date('2026-03-03T11:33:51.077Z'),
  refreshToken: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6IjY5YTU3OTZlMzEzYmMzNjUzOGQwNDVjZSIsImVtYWlsIjoiYWxiaW5vam9obkBtYXJ0ZWxsZWN0LmNvbSIsInJvbGUiOiJBZG1pbiIsImNvbXBhbnlJZCI6IjY5YTU3OTZlMzEzYmMzNjUzOGQwNDVjYSIsImlhdCI6MTc3MjUzNzYzMSwiZXhwIjoxNzczMTQyNDMxfQ.hbnneRK8YHZfAzBkxtrnLZStRn-sE5i5Z7CraeGRixc',
};

async function run() {
  try {
    await connectDB();
    const collection = mongoose.connection.db.collection('users');

    const existing = await collection.findOne({ email: userDoc.email });
    if (existing) {
      console.log('User already exists with email:', userDoc.email);
      console.log('_id:', existing._id);
      process.exit(0);
      return;
    }

    const result = await collection.insertOne(userDoc);
    console.log('User inserted into users collection.');
    console.log('_id:', result.insertedId);
    console.log('email:', userDoc.email);
    process.exit(0);
  } catch (err) {
    console.error('Error:', err.message);
    process.exit(1);
  }
}

run();
