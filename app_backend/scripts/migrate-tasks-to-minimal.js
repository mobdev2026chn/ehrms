#!/usr/bin/env node
/**
 * One-time migration: Move extended fields from tasks to task_details,
 * then strip tasks collection to minimal fields only.
 * Run: node scripts/migrate-tasks-to-minimal.js
 */
require('dotenv').config();
const mongoose = require('mongoose');
const Task = require('../src/models/Task');
const TaskDetails = require('../src/models/TaskDetails');

const EXTENDED_KEYS = [
  'sourceLocation', 'destinationLocation', 'destinationChanged', 'destinations',
  'startLocation', 'startTime', 'started', 'tripDistanceKm', 'tripDurationSeconds',
  'arrivalTime', 'arrived', 'arrivedLatitude', 'arrivedLongitude', 'arrivedFullAddress',
  'arrivedPincode', 'arrivedDate', 'arrivedTime', 'sourceFullAddress',
  'photoProofUrl', 'photoProofUploadedAt', 'photoProofDescription', 'photoProofLat',
  'photoProofLng', 'photoProofAddress', 'otpCode', 'otpSentAt', 'otpVerifiedAt',
  'otpVerifiedLat', 'otpVerifiedLng', 'otpVerifiedAddress', 'progressSteps',
  'isOtpRequired', 'isGeoFenceRequired', 'isPhotoRequired', 'isFormRequired',
  'exit', 'restarted', 'completedDate', 'locationHistory',
];

async function run() {
  await mongoose.connect(process.env.MONGO_URI || process.env.MONGODB_URI);
  const tasks = await Task.find().lean();
  let migrated = 0;
  for (const task of tasks) {
    const taskMongoId = task._id;
    if (!taskMongoId) continue;
    const hasExtended = EXTENDED_KEYS.some((k) => task[k] !== undefined && task[k] !== null);
    if (!hasExtended) continue;
    const details = {};
    for (const k of EXTENDED_KEYS) {
      if (task[k] !== undefined && task[k] !== null) details[k] = task[k];
    }
    if (Object.keys(details).length > 0) {
      await TaskDetails.findOneAndUpdate(
        { taskId: taskMongoId },
        { $set: { ...details, taskId: taskMongoId } },
        { upsert: true }
      );
      const unset = {};
      for (const k of EXTENDED_KEYS) unset[k] = 1;
      await Task.updateOne({ _id: task._id }, { $unset: unset });
      migrated++;
      console.log('Migrated:', task.taskId || taskMongoId);
    }
  }
  console.log('Done. Migrated', migrated, 'of', tasks.length, 'tasks');
  await mongoose.disconnect();
}

run().catch((e) => {
  console.error(e);
  process.exit(1);
});
