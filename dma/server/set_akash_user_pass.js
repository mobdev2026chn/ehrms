const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

async function setPassword() {
  try {
    const uri = process.env.MONGODB_URI || 'mongodb://akashaskeva_db_user:4wdqSQSYRKA76chi@ac-r6pxte7-shard-00-00.wgu7miq.mongodb.net:27017,ac-r6pxte7-shard-00-01.wgu7miq.mongodb.net:27017,ac-r6pxte7-shard-00-02.wgu7miq.mongodb.net:27017/DEV_HRMS?ssl=true&replicaSet=atlas-2gnfgy-shard-0&authSource=admin&appName=ekta';
    await mongoose.connect(uri, { serverSelectionTimeoutMS: 5000 });
    console.log('[Mongo] Connected to DEV_HRMS');

    const db = mongoose.connection.useDb('DEV_HRMS');
    const newHash = bcrypt.hashSync('User@123', 10);

    const updateObj = {
      $set: {
        password: newHash,
        password_hash: newHash,
        passwordHash: newHash
      }
    };

    const res = await db.collection('staffs').updateOne(
      { email: new RegExp('^akash@gmail.com$', 'i') },
      updateObj
    );

    console.log('[Auth Update] Updated akash@gmail.com password to User@123. Modified count:', res.modifiedCount);
  } catch (err) {
    console.error('Error updating password:', err.message);
  }
  process.exit(0);
}

setPassword();
