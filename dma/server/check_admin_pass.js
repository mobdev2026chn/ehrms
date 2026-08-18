const mongoose = require('mongoose');

const uri = 'mongodb://akashaskeva_db_user:4wdqSQSYRKA76chi@ac-r6pxte7-shard-00-00.wgu7miq.mongodb.net:27017,ac-r6pxte7-shard-00-01.wgu7miq.mongodb.net:27017,ac-r6pxte7-shard-00-02.wgu7miq.mongodb.net:27017/DEV_HRMS?ssl=true&replicaSet=atlas-2gnfgy-shard-0&authSource=admin&appName=ekta';

async function checkAdmin() {
  try {
    await mongoose.connect(uri);
    console.log('--- CONNECTED TO MONGO DB ---');
    const targetDb = mongoose.connection.useDb('DEV_HRMS');

    const adminsCol = targetDb.collection('admins');
    const adminsList = await adminsCol.find({}).toArray();
    console.log('\n=== ALL ADMINS IN DB (' + adminsList.length + ') ===');
    adminsList.forEach(a => {
      console.log(`- ID: ${a._id} | Name: ${a.name || a.companyAdmin} | Email: ${a.email} | Pass: ${a.password}`);
    });

    const staffsCol = targetDb.collection('staffs');
    const suganStaff = await staffsCol.find({ email: new RegExp('sugan', 'i') }).toArray();
    console.log('\n=== SUGAN STAFF IN DB (' + suganStaff.length + ') ===');
    suganStaff.forEach(s => {
      console.log(`- ID: ${s._id} | Name: ${s.firstName} ${s.lastName} | Email: ${s.email} | AdminId: ${s.adminId} | Pass: ${s.password}`);
    });

    await mongoose.disconnect();
  } catch (err) {
    console.error('Error:', err);
  }
}

checkAdmin();
